"""
End-to-End Enterprise Retail Sales, Profitability & Customer Experience Analytics
Author: Data Analytics Engineering
Description:
    Performs comprehensive data transformation, RFM customer segmentation,
    shipping SLA delay modeling, discount leakage detection, star-schema generation,
    and SQLite database persistence for the Sample Superstore dataset.
"""

import os
import sqlite3
import pandas as pd
import numpy as np

# 1. Dynamic Paths (Supports any OS and clone location)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
REPO_ROOT = os.path.dirname(PROJECT_DIR)

possible_inputs = [
    os.path.join(PROJECT_DIR, "Sample - Superstore.csv"),
    os.path.join(REPO_ROOT, "Sample - Superstore.csv")
]
DATA_INPUT = next((p for p in possible_inputs if os.path.exists(p)), possible_inputs[0])

DATA_OUTPUT = os.path.join(PROJECT_DIR, "data")
SQL_OUTPUT = os.path.join(PROJECT_DIR, "sql")
DB_PATH = os.path.join(DATA_OUTPUT, "superstore_relational.db")

os.makedirs(DATA_OUTPUT, exist_ok=True)
os.makedirs(SQL_OUTPUT, exist_ok=True)

print("[-] Step 1: Ingesting raw Superstore dataset...")
print(f"    Reading from: {DATA_INPUT}")
df_raw = pd.read_csv(DATA_INPUT, encoding='windows-1252')
print(f"    Raw records: {df_raw.shape[0]}, Columns: {df_raw.shape[1]}")

# 2. Data Cleaning & Date Normalization
print("[-] Step 2: Cleaning and Standardizing Transactions...")
df_clean = df_raw.copy()

df_clean['Order Date'] = pd.to_datetime(df_clean['Order Date'])
df_clean['Ship Date'] = pd.to_datetime(df_clean['Ship Date'])

df_clean['Order_Year'] = df_clean['Order Date'].dt.year
df_clean['Order_Quarter'] = df_clean['Order Date'].dt.to_period('Q').astype(str)
df_clean['Order_Month'] = df_clean['Order Date'].dt.month
df_clean['Order_Year_Month'] = df_clean['Order Date'].dt.strftime('%Y-%m')

df_clean['Shipping_Duration_Days'] = (df_clean['Ship Date'] - df_clean['Order Date']).dt.days
df_clean['Postal Code'] = df_clean['Postal Code'].astype(str).str.zfill(5)

df_clean['Profit_Margin_Pct'] = np.where(df_clean['Sales'] > 0, df_clean['Profit'] / df_clean['Sales'], 0.0)
df_clean['Unit_Price'] = round(df_clean['Sales'] / df_clean['Quantity'], 2)
df_clean['Unit_Cost'] = round((df_clean['Sales'] - df_clean['Profit']) / df_clean['Quantity'], 2)

# 3. Supply Chain Shipping SLA Compliance Modeling
print("[-] Step 3: Engineering Shipping SLA & Delay Metrics...")

def evaluate_shipping_sla(row):
    mode = row['Ship Mode']
    days = row['Shipping_Duration_Days']
    
    if mode == 'Same Day':
        sla_target = 0
    elif mode == 'First Class':
        sla_target = 2
    elif mode == 'Second Class':
        sla_target = 3
    else:
        sla_target = 5
        
    delay_days = max(0, days - sla_target)
    
    if delay_days == 0:
        sla_status = 'On-Time / Met SLA'
        sla_breach_flag = 0
    elif delay_days <= 2:
        sla_status = 'Minor Delay (1-2 Days)'
        sla_breach_flag = 1
    else:
        sla_status = 'Severe Delay (3+ Days)'
        sla_breach_flag = 1
        
    return pd.Series([sla_target, delay_days, sla_status, sla_breach_flag])

df_clean[['SLA_Target_Days', 'Delay_Days', 'Shipping_SLA_Status', 'SLA_Breach_Flag']] = df_clean.apply(evaluate_shipping_sla, axis=1)

# 4. Feature Engineering
print("[-] Step 4: Engineering Profit Leakage & Discount Elasticity Indicators...")

df_clean['Discount_Leakage_Flag'] = df_clean.apply(
    lambda r: 1 if (r['Discount'] >= 0.20 and r['Profit'] < 0) else 0,
    axis=1
)

def assign_discount_tier(disc):
    if disc == 0.0:
        return '0% Full Price (Zero Discount)'
    elif disc <= 0.15:
        return '1% - 15% (Modest Discount)'
    elif disc <= 0.30:
        return '16% - 30% (Aggressive Discount)'
    elif disc <= 0.50:
        return '31% - 50% (High Margin Risk)'
    else:
        return '51%+ (Severe Destruction)'

df_clean['Discount_Tier'] = df_clean['Discount'].apply(assign_discount_tier)

def assign_profit_tier(profit):
    if profit > 200:
        return 'High Profit (>$200)'
    elif profit > 0:
        return 'Profitable ($0-$200)'
    elif profit == 0:
        return 'Break-even ($0)'
    elif profit > -100:
        return 'Moderate Loss (-$1 to -$100)'
    else:
        return 'Severe Loss (<-$100)'

df_clean['Profit_Health_Tier'] = df_clean['Profit'].apply(assign_profit_tier)

# 5. Customer RFM Segmentation
print("[-] Step 5: Computing Customer RFM Metrics & Churn Risk...")
ref_date = df_clean['Order Date'].max() + pd.Timedelta(days=1)

cust_summary = df_clean.groupby('Customer ID').agg(
    Recency_Days=('Order Date', lambda x: (ref_date - x.max()).days),
    Frequency_Orders=('Order ID', 'nunique'),
    Monetary_Total_Sales=('Sales', 'sum'),
    Total_Profit=('Profit', 'sum'),
    Total_Quantity=('Quantity', 'sum'),
    First_Order_Date=('Order Date', 'min'),
    Last_Order_Date=('Order Date', 'max')
).reset_index()

cust_summary['R_Score'] = pd.qcut(cust_summary['Recency_Days'], 5, labels=[5, 4, 3, 2, 1]).astype(int)
cust_summary['F_Score'] = pd.qcut(cust_summary['Frequency_Orders'].rank(method='first'), 5, labels=[1, 2, 3, 4, 5]).astype(int)
cust_summary['M_Score'] = pd.qcut(cust_summary['Monetary_Total_Sales'], 5, labels=[1, 2, 3, 4, 5]).astype(int)

cust_summary['RFM_Composite'] = cust_summary['R_Score'] * 100 + cust_summary['F_Score'] * 10 + cust_summary['M_Score']

rfm_segments = []
churn_risk_tiers = []

for _, r in cust_summary.iterrows():
    r_score = r['R_Score']
    f_score = r['F_Score']
    m_score = r['M_Score']
    
    if r_score >= 4 and f_score >= 4 and m_score >= 4:
        seg = 'Champions'
        churn = 'Low Churn Risk / Highly Active'
    elif r_score >= 3 and f_score >= 3:
        seg = 'Loyal Customers'
        churn = 'Low Churn Risk / Active'
    elif r_score >= 4 and f_score <= 2:
        seg = 'Recent Customers / New Growth'
        churn = 'Moderate Churn Risk / Onboarding'
    elif r_score >= 3 and m_score >= 3:
        seg = 'Potential Loyalists'
        churn = 'Moderate Churn Risk'
    elif r_score <= 2 and f_score >= 3:
        seg = 'At Risk / Need Attention'
        churn = 'High Churn Risk'
    elif r_score <= 2 and f_score <= 2 and m_score >= 3:
        seg = 'At Risk High Spenders'
        churn = 'Critical Churn Risk (High Value Attrition)'
    else:
        seg = 'Hibernating / Lapsed'
        churn = 'Lapsed / Dormant Churn'
        
    rfm_segments.append(seg)
    churn_risk_tiers.append(churn)

cust_summary['RFM_Segment'] = rfm_segments
cust_summary['Customer_Churn_Risk'] = churn_risk_tiers

df_clean = df_clean.merge(
    cust_summary[['Customer ID', 'Recency_Days', 'Frequency_Orders', 'RFM_Composite', 'RFM_Segment', 'Customer_Churn_Risk']], 
    on='Customer ID', 
    how='left'
)

# 6. Export Master Cleaned Dataset
master_csv = os.path.join(DATA_OUTPUT, "superstore_commercial_master.csv")
df_clean.to_csv(master_csv, index=False)
print(f"[-] Master dataset saved to: {master_csv}")

# 7. Relational Star-Schema Normalization
print("[-] Step 6: Normalizing into Relational Star-Schema Tables...")

dim_customer = cust_summary[[
    'Customer ID', 'Recency_Days', 'Frequency_Orders', 'Monetary_Total_Sales',
    'Total_Profit', 'R_Score', 'F_Score', 'M_Score', 'RFM_Composite',
    'RFM_Segment', 'Customer_Churn_Risk'
]].copy()

cust_meta = df_clean[['Customer ID', 'Customer Name', 'Segment']].drop_duplicates()
dim_customer = dim_customer.merge(cust_meta, on='Customer ID', how='left')
dim_customer.to_csv(os.path.join(DATA_OUTPUT, "dim_customer.csv"), index=False)

dim_product = df_clean[['Product ID', 'Category', 'Sub-Category', 'Product Name']].drop_duplicates()
dim_product.to_csv(os.path.join(DATA_OUTPUT, "dim_product.csv"), index=False)

dim_geography = df_clean[['Postal Code', 'City', 'State', 'Region', 'Country']].drop_duplicates()
dim_geography.to_csv(os.path.join(DATA_OUTPUT, "dim_geography.csv"), index=False)

dim_shipping = pd.DataFrame({
    'Ship_Mode_ID': [1, 2, 3, 4],
    'Ship Mode': ['Same Day', 'First Class', 'Second Class', 'Standard Class'],
    'Target_SLA_Days': [0, 2, 3, 5],
    'Priority_Level': ['Ultra Expedited', 'Express', 'Standard Plus', 'Ground Economy']
})
dim_shipping.to_csv(os.path.join(DATA_OUTPUT, "dim_shipping.csv"), index=False)

fact_orders = df_clean[[
    'Row ID', 'Order ID', 'Order Date', 'Ship Date', 'Order_Year', 'Order_Quarter', 
    'Order_Month', 'Order_Year_Month', 'Ship Mode', 'Customer ID', 'Postal Code', 
    'Product ID', 'Sales', 'Quantity', 'Discount', 'Profit', 'Profit_Margin_Pct',
    'Shipping_Duration_Days', 'Delay_Days', 'Shipping_SLA_Status', 'SLA_Breach_Flag',
    'Discount_Tier', 'Profit_Health_Tier', 'Discount_Leakage_Flag'
]].copy()
fact_orders.to_csv(os.path.join(DATA_OUTPUT, "fact_sales_orders.csv"), index=False)

# 8. Persist to SQLite
print("[-] Step 7: Creating SQLite Relational Database and Indexes...")
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

dim_customer.to_sql('dim_customer', conn, if_exists='replace', index=False)
dim_product.to_sql('dim_product', conn, if_exists='replace', index=False)
dim_geography.to_sql('dim_geography', conn, if_exists='replace', index=False)
dim_shipping.to_sql('dim_shipping', conn, if_exists='replace', index=False)
fact_orders.to_sql('fact_sales_orders', conn, if_exists='replace', index=False)

cursor.execute("CREATE INDEX IF NOT EXISTS idx_ord_cust ON fact_sales_orders([Customer ID])")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_ord_prod ON fact_sales_orders([Product ID])")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_ord_date ON fact_sales_orders([Order Date])")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_ord_geo ON fact_sales_orders([Postal Code])")

conn.commit()
conn.close()
print(f"[-] SQLite Database successfully built at: {DB_PATH}")
print("[+] Project 2 Python Analysis and Data Transformation Complete!\n")
