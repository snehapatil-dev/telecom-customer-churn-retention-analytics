// ==============================================================================
// PROJECT 2: ENTERPRISE RETAIL SALES, PROFITABILITY & SUPPLY CHAIN ANALYTICS
// Power Query M Scripts for Microsoft Power BI Desktop
// Ingests, Cleans, Enriches, and Models Star-Schema Tables
// ==============================================================================

// ------------------------------------------------------------------------------
// QUERY 1: [ Raw_Superstore_Source ]
// Loads Master Enriched Transactions CSV
// ------------------------------------------------------------------------------
let
    SourcePath = "D:\SP\Project2_Superstore_Analytics\data\superstore_commercial_master.csv",
    Source = Csv.Document(File.Contents(SourcePath),[Delimiter=",", Columns=37, Encoding=1252, QuoteStyle=QuoteStyle.None]),
    PromotedHeaders = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    
    ChangedTypes = Table.TransformColumnTypes(PromotedHeaders,{
        {"Row ID", Int64.Type},
        {"Order ID", type text},
        {"Order Date", type date},
        {"Ship Date", type date},
        {"Ship Mode", type text},
        {"Customer ID", type text},
        {"Customer Name", type text},
        {"Segment", type text},
        {"Country", type text},
        {"City", type text},
        {"State", type text},
        {"Postal Code", type text},
        {"Region", type text},
        {"Product ID", type text},
        {"Category", type text},
        {"Sub-Category", type text},
        {"Product Name", type text},
        {"Sales", type number},
        {"Quantity", Int64.Type},
        {"Discount", type number},
        {"Profit", type number},
        {"Order_Year", Int64.Type},
        {"Order_Quarter", type text},
        {"Order_Month", Int64.Type},
        {"Order_Year_Month", type text},
        {"Shipping_Duration_Days", Int64.Type},
        {"Profit_Margin_Pct", type number},
        {"Unit_Price", type number},
        {"Unit_Cost", type number},
        {"SLA_Target_Days", Int64.Type},
        {"Delay_Days", Int64.Type},
        {"Shipping_SLA_Status", type text},
        {"SLA_Breach_Flag", Int64.Type},
        {"Discount_Leakage_Flag", Int64.Type},
        {"Discount_Tier", type text},
        {"Profit_Health_Tier", type text},
        {"Recency_Days", Int64.Type},
        {"Frequency_Orders", Int64.Type},
        {"RFM_Composite", Int64.Type},
        {"RFM_Segment", type text},
        {"Customer_Churn_Risk", type text}
    })
in
    ChangedTypes

// ------------------------------------------------------------------------------
// QUERY 2: [ dim_customer ]
// Dimension Table: Customer Profiles & RFM Metrics
// ------------------------------------------------------------------------------
let
    Source = Raw_Superstore_Source,
    SelectColumns = Table.SelectColumns(Source, {
        "Customer ID", "Customer Name", "Segment", "Recency_Days", 
        "Frequency_Orders", "RFM_Composite", "RFM_Segment", "Customer_Churn_Risk"
    }),
    RemovedDuplicates = Table.Distinct(SelectColumns, {"Customer ID"})
in
    RemovedDuplicates

// ------------------------------------------------------------------------------
// QUERY 3: [ dim_product ]
// Dimension Table: Product Hierarchy (Category > Sub-Category > Product)
// ------------------------------------------------------------------------------
let
    Source = Raw_Superstore_Source,
    SelectColumns = Table.SelectColumns(Source, {"Product ID", "Category", "Sub-Category", "Product Name"}),
    RemovedDuplicates = Table.Distinct(SelectColumns, {"Product ID"})
in
    RemovedDuplicates

// ------------------------------------------------------------------------------
// QUERY 4: [ dim_geography ]
// Dimension Table: Geographic Hierarchy (Country > Region > State > City > Zip)
// ------------------------------------------------------------------------------
let
    Source = Raw_Superstore_Source,
    SelectColumns = Table.SelectColumns(Source, {"Postal Code", "City", "State", "Region", "Country"}),
    RemovedDuplicates = Table.Distinct(SelectColumns, {"Postal Code"})
in
    RemovedDuplicates

// ------------------------------------------------------------------------------
// QUERY 5: [ fact_sales_orders ]
// Fact Table: Transaction Level Orders
// ------------------------------------------------------------------------------
let
    Source = Raw_Superstore_Source,
    SelectColumns = Table.SelectColumns(Source, {
        "Row ID", "Order ID", "Order Date", "Ship Date", "Order_Year", "Order_Quarter", 
        "Order_Month", "Order_Year_Month", "Ship Mode", "Customer ID", "Postal Code", 
        "Product ID", "Sales", "Quantity", "Discount", "Profit", "Profit_Margin_Pct",
        "Shipping_Duration_Days", "Delay_Days", "Shipping_SLA_Status", "SLA_Breach_Flag",
        "Discount_Tier", "Profit_Health_Tier", "Discount_Leakage_Flag"
    })
in
    SelectColumns

// ------------------------------------------------------------------------------
// QUERY 6: [ dim_calendar ]
// Automated Date Dimension Table for Time Intelligence
// ------------------------------------------------------------------------------
let
    StartDate = #date(2014, 1, 1),
    EndDate = #date(2017, 12, 31),
    DayCount = Duration.Days(Duration.From(EndDate - StartDate)) + 1,
    Source = List.Dates(StartDate, DayCount, #duration(1, 0, 0, 0)),
    TableFromList = Table.FromList(Source, Splitter.SplitByNothing(), {"Date"}, null, ExtraValues.Error),
    ChangedType = Table.TransformColumnTypes(TableFromList,{{"Date", type date}}),
    AddYear = Table.AddColumn(ChangedType, "Year", each Date.Year([Date]), Int64.Type),
    AddQuarter = Table.AddColumn(AddYear, "Quarter", each "Q" & Text.From(Date.QuarterOfYear([Date])), type text),
    AddMonth = Table.AddColumn(AddQuarter, "Month", each Date.Month([Date]), Int64.Type),
    AddMonthName = Table.AddColumn(AddMonth, "Month Name", each Date.MonthName([Date]), type text),
    AddYearMonth = Table.AddColumn(AddMonthName, "Year-Month", each Text.From(Date.Year([Date])) & "-" & Text.PadStart(Text.From(Date.Month([Date])), 2, "0"), type text)
in
    AddYearMonth
