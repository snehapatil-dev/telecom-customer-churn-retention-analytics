-- ==============================================================================
-- PROJECT 2: ENTERPRISE RETAIL SALES, PROFITABILITY & SUPPLY CHAIN ANALYTICS
-- Database Dialect: MySQL 8.0+
-- Compatible with: MySQL Workbench, AWS RDS MySQL, Google Cloud SQL, phpMyAdmin
-- Features: InnoDB Engine, Star-Schema Relational DDL, CTEs, Window Functions
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. DATABASE CREATION & CONTEXT
-- ------------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS superstore_commercial_analytics;
USE superstore_commercial_analytics;

SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- ------------------------------------------------------------------------------
-- 1. RELATIONAL SCHEMA DDL (STAR-SCHEMA DESIGN)
-- ------------------------------------------------------------------------------

DROP TABLE IF EXISTS fact_sales_orders;
DROP TABLE IF EXISTS dim_shipping;
DROP TABLE IF EXISTS dim_geography;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_customer;

-- Dimension 1: Customer Master & RFM Profile
CREATE TABLE dim_customer (
    `Customer ID` VARCHAR(20) NOT NULL,
    `Customer Name` VARCHAR(100) NOT NULL,
    Segment VARCHAR(30) NOT NULL,
    Recency_Days INT NOT NULL,
    Frequency_Orders INT NOT NULL,
    Monetary_Total_Sales DECIMAL(12, 2) NOT NULL,
    Total_Profit DECIMAL(12, 2) NOT NULL,
    R_Score INT NOT NULL,
    F_Score INT NOT NULL,
    M_Score INT NOT NULL,
    RFM_Composite INT NOT NULL,
    RFM_Segment VARCHAR(50) NOT NULL,
    Customer_Churn_Risk VARCHAR(60) NOT NULL,
    PRIMARY KEY (`Customer ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dimension 2: Product Hierarchy
CREATE TABLE dim_product (
    `Product ID` VARCHAR(30) NOT NULL,
    Category VARCHAR(40) NOT NULL,
    `Sub-Category` VARCHAR(40) NOT NULL,
    `Product Name` VARCHAR(255) NOT NULL,
    PRIMARY KEY (`Product ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dimension 3: Geography & Territory
CREATE TABLE dim_geography (
    `Postal Code` VARCHAR(10) NOT NULL,
    City VARCHAR(60) NOT NULL,
    State VARCHAR(60) NOT NULL,
    Region VARCHAR(30) NOT NULL,
    Country VARCHAR(30) NOT NULL,
    PRIMARY KEY (`Postal Code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dimension 4: Shipping Mode SLA
CREATE TABLE dim_shipping (
    Ship_Mode_ID INT NOT NULL AUTO_INCREMENT,
    `Ship Mode` VARCHAR(30) NOT NULL,
    Target_SLA_Days INT NOT NULL,
    Priority_Level VARCHAR(30) NOT NULL,
    PRIMARY KEY (Ship_Mode_ID),
    UNIQUE KEY uq_ship_mode (`Ship Mode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Populate Shipping SLAs
INSERT INTO dim_shipping (`Ship Mode`, Target_SLA_Days, Priority_Level) VALUES
('Same Day', 0, 'Ultra Expedited'),
('First Class', 2, 'Express'),
('Second Class', 3, 'Standard Plus'),
('Standard Class', 5, 'Ground Economy');

-- Fact Table: Sales Orders Transactions
CREATE TABLE fact_sales_orders (
    `Row ID` INT NOT NULL,
    `Order ID` VARCHAR(30) NOT NULL,
    `Order Date` DATE NOT NULL,
    `Ship Date` DATE NOT NULL,
    Order_Year INT NOT NULL,
    Order_Quarter VARCHAR(10) NOT NULL,
    Order_Month INT NOT NULL,
    Order_Year_Month VARCHAR(10) NOT NULL,
    `Ship Mode` VARCHAR(30) NOT NULL,
    `Customer ID` VARCHAR(20) NOT NULL,
    `Postal Code` VARCHAR(10) NOT NULL,
    `Product ID` VARCHAR(30) NOT NULL,
    Sales DECIMAL(12, 2) NOT NULL,
    Quantity INT NOT NULL,
    Discount DECIMAL(4, 2) NOT NULL,
    Profit DECIMAL(12, 2) NOT NULL,
    Profit_Margin_Pct DECIMAL(6, 4) NOT NULL,
    Shipping_Duration_Days INT NOT NULL,
    Delay_Days INT NOT NULL,
    Shipping_SLA_Status VARCHAR(40) NOT NULL,
    SLA_Breach_Flag TINYINT NOT NULL,
    Discount_Tier VARCHAR(40) NOT NULL,
    Profit_Health_Tier VARCHAR(40) NOT NULL,
    Discount_Leakage_Flag TINYINT NOT NULL,
    PRIMARY KEY (`Row ID`),
    CONSTRAINT fk_ord_customer FOREIGN KEY (`Customer ID`) 
        REFERENCES dim_customer(`Customer ID`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ord_product FOREIGN KEY (`Product ID`) 
        REFERENCES dim_product(`Product ID`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ord_geography FOREIGN KEY (`Postal Code`) 
        REFERENCES dim_geography(`Postal Code`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Indexes for Query Performance
CREATE INDEX idx_fact_ord_date ON fact_sales_orders(`Order Date`);
CREATE INDEX idx_fact_ord_year ON fact_sales_orders(Order_Year);
CREATE INDEX idx_fact_ord_leakage ON fact_sales_orders(Discount_Leakage_Flag);
CREATE INDEX idx_dim_cust_segment ON dim_customer(Segment);
CREATE INDEX idx_dim_cust_rfm ON dim_customer(RFM_Segment);
CREATE INDEX idx_dim_prod_cat ON dim_product(Category);
CREATE INDEX idx_dim_prod_subcat ON dim_product(`Sub-Category`);
CREATE INDEX idx_dim_geo_region ON dim_geography(Region);
CREATE INDEX idx_dim_geo_state ON dim_geography(State);

-- ------------------------------------------------------------------------------
-- 2. ANALYTICAL VIEW 1: COMMERCIAL 360 COMPREHENSIVE VIEW
-- Multi-table relational joins connecting Customer, Product, Geography & Fact
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_commercial_360_orders AS
SELECT 
    f.`Row ID`,
    f.`Order ID`,
    f.`Order Date`,
    f.`Ship Date`,
    f.Order_Year,
    f.Order_Quarter,
    f.Order_Year_Month,
    c.`Customer ID`,
    c.`Customer Name`,
    c.Segment,
    c.RFM_Segment,
    c.Customer_Churn_Risk,
    p.`Product ID`,
    p.Category,
    p.`Sub-Category`,
    p.`Product Name`,
    g.`Postal Code`,
    g.City,
    g.State,
    g.Region,
    f.`Ship Mode`,
    f.Shipping_Duration_Days,
    f.Delay_Days,
    f.Shipping_SLA_Status,
    f.SLA_Breach_Flag,
    f.Sales,
    f.Quantity,
    f.Discount,
    f.Profit,
    f.Profit_Margin_Pct,
    f.Discount_Tier,
    f.Profit_Health_Tier,
    f.Discount_Leakage_Flag
FROM fact_sales_orders f
INNER JOIN dim_customer c ON f.`Customer ID` = c.`Customer ID`
INNER JOIN dim_product p ON f.`Product ID` = p.`Product ID`
INNER JOIN dim_geography g ON f.`Postal Code` = g.`Postal Code`;

-- ------------------------------------------------------------------------------
-- 3. COMPLEX QUERY 1: PARETO 80/20 PRODUCT PERFORMANCE (WINDOW FUNCTION)
-- Cumulative revenue calculation identifying top-performing revenue drivers
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pareto_80_20_products AS
WITH ProductSalesSummary AS (
    SELECT 
        p.`Product ID`,
        p.`Product Name`,
        p.Category,
        p.`Sub-Category`,
        ROUND(SUM(f.Sales), 2) AS Total_Sales,
        ROUND(SUM(f.Profit), 2) AS Total_Profit,
        SUM(f.Quantity) AS Total_Quantity
    FROM fact_sales_orders f
    INNER JOIN dim_product p ON f.`Product ID` = p.`Product ID`
    GROUP BY p.`Product ID`, p.`Product Name`, p.Category, p.`Sub-Category`
),
RankedProducts AS (
    SELECT 
        `Product ID`,
        `Product Name`,
        Category,
        `Sub-Category`,
        Total_Sales,
        Total_Profit,
        Total_Quantity,
        ROW_NUMBER() OVER (ORDER BY Total_Sales DESC) AS Sales_Rank,
        SUM(Total_Sales) OVER () AS Grand_Total_Sales,
        SUM(Total_Sales) OVER (
            ORDER BY Total_Sales DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS Running_Total_Sales
    FROM ProductSalesSummary
)
SELECT 
    Sales_Rank,
    `Product ID`,
    `Product Name`,
    Category,
    `Sub-Category`,
    Total_Sales,
    Total_Profit,
    Total_Quantity,
    Running_Total_Sales,
    ROUND((Running_Total_Sales * 100.0) / Grand_Total_Sales, 2) AS Cumulative_Sales_Pct,
    CASE 
        WHEN (Running_Total_Sales * 100.0) / Grand_Total_Sales <= 80.0 THEN 'Core 80% Revenue Generator'
        ELSE 'Long-Tail 20% Contributor'
    END AS Pareto_Classification
FROM RankedProducts;

-- ------------------------------------------------------------------------------
-- 4. COMPLEX QUERY 2: YEAR-OVER-YEAR (YoY) SALES & PROFIT GROWTH VIEW
-- Uses MySQL 8.0 LAG() Window Function across Category and Fiscal Year
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_yoy_sales_profit_growth AS
WITH CategoryYearlySummary AS (
    SELECT 
        p.Category,
        f.Order_Year,
        ROUND(SUM(f.Sales), 2) AS Annual_Sales,
        ROUND(SUM(f.Profit), 2) AS Annual_Profit,
        ROUND(AVG(f.Profit_Margin_Pct) * 100.0, 2) AS Avg_Profit_Margin_Pct,
        COUNT(DISTINCT f.`Order ID`) AS Total_Orders
    FROM fact_sales_orders f
    INNER JOIN dim_product p ON f.`Product ID` = p.`Product ID`
    GROUP BY p.Category, f.Order_Year
),
YoYCalculations AS (
    SELECT 
        Category,
        Order_Year,
        Annual_Sales,
        Annual_Profit,
        Avg_Profit_Margin_Pct,
        Total_Orders,
        LAG(Annual_Sales, 1) OVER (PARTITION BY Category ORDER BY Order_Year) AS Prev_Year_Sales,
        LAG(Annual_Profit, 1) OVER (PARTITION BY Category ORDER BY Order_Year) AS Prev_Year_Profit
    FROM CategoryYearlySummary
)
SELECT 
    Category,
    Order_Year,
    Annual_Sales,
    Prev_Year_Sales,
    ROUND(
        CASE 
            WHEN Prev_Year_Sales IS NULL THEN 0.0
            ELSE ((Annual_Sales - Prev_Year_Sales) * 100.0) / Prev_Year_Sales
        END, 2
    ) AS YoY_Sales_Growth_Pct,
    Annual_Profit,
    Prev_Year_Profit,
    ROUND(
        CASE 
            WHEN Prev_Year_Profit IS NULL THEN 0.0
            ELSE ((Annual_Profit - Prev_Year_Profit) * 100.0) / ABS(Prev_Year_Profit)
        END, 2
    ) AS YoY_Profit_Growth_Pct,
    Avg_Profit_Margin_Pct,
    Total_Orders
FROM YoYCalculations;

-- ------------------------------------------------------------------------------
-- 5. COMPLEX QUERY 3: SUB-CATEGORY DISCOUNT ELASTICITY & PROFIT LEAKAGE
-- Evaluates gross margin erosion and identifies sub-categories in structural loss
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_subcat_discount_leakage AS
WITH DiscountSubCatSummary AS (
    SELECT 
        p.Category,
        p.`Sub-Category`,
        f.Discount_Tier,
        COUNT(f.`Row ID`) AS Transaction_Count,
        ROUND(SUM(f.Sales), 2) AS Total_Sales,
        ROUND(SUM(f.Profit), 2) AS Total_Profit,
        SUM(f.Discount_Leakage_Flag) AS Leakage_Transactions,
        ROUND(AVG(f.Discount) * 100.0, 2) AS Avg_Discount_Pct,
        ROUND(
            CASE 
                WHEN SUM(f.Sales) > 0 THEN (SUM(f.Profit) * 100.0) / SUM(f.Sales)
                ELSE 0.0
            END, 2
        ) AS Realized_Margin_Pct
    FROM fact_sales_orders f
    INNER JOIN dim_product p ON f.`Product ID` = p.`Product ID`
    GROUP BY p.Category, p.`Sub-Category`, f.Discount_Tier
)
SELECT 
    Category,
    `Sub-Category`,
    Discount_Tier,
    Transaction_Count,
    Total_Sales,
    Total_Profit,
    Realized_Margin_Pct,
    Leakage_Transactions,
    ROUND((Leakage_Transactions * 100.0) / Transaction_Count, 2) AS Leakage_Tx_Pct,
    CASE 
        WHEN Realized_Margin_Pct < -10.0 THEN '🚨 Severe Margin Bleed'
        WHEN Realized_Margin_Pct < 0.0 THEN '⚠️ Negative Margin Drain'
        WHEN Realized_Margin_Pct < 15.0 THEN '🟡 Low Margin'
        ELSE '🟢 Healthy Margin'
    END AS Margin_Health_Indicator
FROM DiscountSubCatSummary;

-- ------------------------------------------------------------------------------
-- 6. COMPLEX QUERY 4: CUSTOMER CLV DECILE RANKING (WINDOW FUNCTION NTILE)
-- Segments customer base into spend deciles and computes cumulative contribution
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_clv_deciles AS
WITH CustomerDeciles AS (
    SELECT 
        `Customer ID`,
        `Customer Name`,
        Segment,
        RFM_Segment,
        Customer_Churn_Risk,
        Monetary_Total_Sales,
        Total_Profit,
        Frequency_Orders,
        Recency_Days,
        NTILE(10) OVER (ORDER BY Monetary_Total_Sales DESC) AS Spend_Decile,
        DENSE_RANK() OVER (ORDER BY Monetary_Total_Sales DESC) AS Spend_Rank
    FROM dim_customer
)
SELECT 
    Spend_Decile,
    COUNT(`Customer ID`) AS Customer_Count,
    ROUND(SUM(Monetary_Total_Sales), 2) AS Decile_Sales,
    ROUND(SUM(Total_Profit), 2) AS Decile_Profit,
    ROUND(AVG(Monetary_Total_Sales), 2) AS Avg_Spend_Per_Customer,
    ROUND(AVG(Frequency_Orders), 1) AS Avg_Orders_Per_Customer,
    ROUND(AVG(Recency_Days), 0) AS Avg_Recency_Days,
    ROUND(
        (SUM(Monetary_Total_Sales) * 100.0) / (SELECT SUM(Monetary_Total_Sales) FROM dim_customer), 2
    ) AS Pct_Of_Total_Revenue
FROM CustomerDeciles
GROUP BY Spend_Decile;

-- ------------------------------------------------------------------------------
-- 7. COMPLEX QUERY 5: SUPPLY CHAIN SHIPPING SLA & REGIONAL DELAY MATRIX
-- Analyzes fulfillment SLA compliance by carrier mode and geography
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_shipping_sla_regional_matrix AS
SELECT 
    g.Region,
    f.`Ship Mode`,
    COUNT(f.`Row ID`) AS Total_Shipments,
    SUM(f.SLA_Breach_Flag) AS Delayed_Shipments,
    ROUND(AVG(f.Shipping_Duration_Days), 2) AS Avg_Shipping_Days,
    ROUND(AVG(f.Delay_Days), 2) AS Avg_Delay_Days,
    ROUND(
        (SUM(f.SLA_Breach_Flag) * 100.0) / COUNT(f.`Row ID`), 2
    ) AS SLA_Breach_Rate_Pct,
    ROUND(
        100.0 - ((SUM(f.SLA_Breach_Flag) * 100.0) / COUNT(f.`Row ID`)), 2
    ) AS On_Time_Fulfillment_Pct
FROM fact_sales_orders f
INNER JOIN dim_geography g ON f.`Postal Code` = g.`Postal Code`
GROUP BY g.Region, f.`Ship Mode`;
