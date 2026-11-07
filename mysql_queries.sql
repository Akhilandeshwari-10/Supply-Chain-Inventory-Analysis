
-- =====================================================
-- 1. LATE SHIPMENT BY SHIPPING MODE
-- Purpose: Analyze delivery delays by shipping mode
-- =====================================================

SELECT
    Shipping_Mode AS shipping_mode,
    COUNT(*) AS total_orders,

    SUM(
        CASE
            WHEN Late_delivery_risk = 1 THEN 1
            ELSE 0
        END
    ) AS late_orders,

    ROUND(
        SUM(
            CASE
                WHEN Late_delivery_risk = 1 THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS late_pct,

    ROUND(
        AVG(
            CAST(`Days_for_shipping_(real)` AS DECIMAL(10,2))
            - CAST(`Days_for_shipment_(scheduled)` AS DECIMAL(10,2))
        ),
        2
    ) AS avg_delay_days

FROM orders
GROUP BY Shipping_Mode
ORDER BY late_pct DESC;


-- =====================================================
-- 2. LATE SHIPMENT BY REGION
-- Purpose: Analyze delivery delays by region and shipping mode
-- =====================================================

SELECT
    `Order_Region` AS region,
    `Shipping_Mode` AS shipping_mode,
    COUNT(*) AS total_orders,

    ROUND(
        SUM(
            CASE
                WHEN Late_delivery_risk = 1 THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        1
    ) AS late_pct

FROM orders
GROUP BY
    `Order_Region`,
    `Shipping_Mode`

HAVING COUNT(*) >= 50

ORDER BY late_pct DESC;

-- =====================================================
-- 3. REPLENISHMENT RISK BY PRODUCT
-- Purpose: Identify products with higher replenishment burden
-- Note: This is a risk proxy, not an actual stockout prediction.
-- =====================================================

WITH product_demand AS (
    SELECT
        `Product_Name` AS product_name,
        `Category_Name` AS category_name,
        COUNT(*) AS order_count,

        ROUND(
            AVG(CAST(`Order_Item_Quantity` AS DECIMAL(10,2))),
            2
        ) AS avg_order_quantity,

        ROUND(
            AVG(CAST(`Days_for_shipping_(real)` AS DECIMAL(10,2))),
            2
        ) AS avg_lead_time_days,

        ROUND(
            AVG(CAST(`Order_Item_Quantity` AS DECIMAL(10,2)))
            *
            AVG(CAST(`Days_for_shipping_(real)` AS DECIMAL(10,2))),
            2
        ) AS replenishment_burden

    FROM orders
    GROUP BY `Product_Name`, `Category_Name`
    HAVING COUNT(*) >= 30
)

SELECT
    *,
    NTILE(4) OVER (
        ORDER BY replenishment_burden DESC
    ) AS risk_quartile

FROM product_demand
ORDER BY replenishment_burden DESC
LIMIT 25;

-- =====================================================
-- 4. MARKET RELIABILITY
-- Purpose: Evaluate delivery reliability across markets
-- =====================================================

WITH market_orders AS (
    SELECT
        Market AS market,
        `Order_Region` AS region,
        Late_delivery_risk,
        CAST(`Order_Item_Profit_Ratio` AS DECIMAL(10,4))
            AS profit_ratio
    FROM orders
)

SELECT
    market,
    COUNT(*) AS total_orders,

    ROUND(
        100.0 - SUM(
            CASE
                WHEN Late_delivery_risk = 1 THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        1
    ) AS on_time_pct,

    ROUND(AVG(profit_ratio), 3) AS avg_profit_ratio,

    COUNT(DISTINCT region) AS regions_served

FROM market_orders
GROUP BY market
ORDER BY on_time_pct DESC;

-- =====================================================
-- 5. RFM ANALYSIS
-- Purpose: Calculate customer RFM scores and segments
-- Recency: Days since last order
-- Frequency: Distinct order dates
-- Monetary: Total customer spending
-- =====================================================

CREATE OR REPLACE VIEW rfm_analysis AS

WITH customer_orders AS (
    SELECT
        `Order_Customer_Id` AS customer_id,

        DATE(
            STR_TO_DATE(
                `order_date_(DateOrders)`,
                '%m/%d/%Y %H:%i'
            )
        ) AS order_date,

        CAST(`Order_Item_Total` AS DECIMAL(12,2)) AS order_total

    FROM orders
),

max_date AS (
    SELECT MAX(order_date) AS d
    FROM customer_orders
),

customer_agg AS (
    SELECT
        customer_id,
        MAX(order_date) AS last_order_date,
        COUNT(DISTINCT order_date) AS frequency,
        ROUND(SUM(order_total), 2) AS monetary

    FROM customer_orders
    GROUP BY customer_id
),

scored AS (
    SELECT
        c.customer_id,

        DATEDIFF(m.d, c.last_order_date) AS recency_days,
        c.frequency,
        c.monetary,

        NTILE(4) OVER (
            ORDER BY DATEDIFF(m.d, c.last_order_date) DESC
        ) AS recency_score,

        NTILE(4) OVER (
            ORDER BY c.frequency ASC
        ) AS frequency_score,

        NTILE(4) OVER (
            ORDER BY c.monetary ASC
        ) AS monetary_score

    FROM customer_agg c
    CROSS JOIN max_date m
)

SELECT
    *,
    recency_score + frequency_score + monetary_score AS rfm_score,

    CASE
        WHEN recency_score + frequency_score + monetary_score >= 10
            THEN 'Champions'
        WHEN recency_score + frequency_score + monetary_score >= 7
            THEN 'Loyal'
        WHEN recency_score + frequency_score + monetary_score >= 4
            THEN 'At Risk'
        ELSE 'Lost'
    END AS segment

FROM scored;

-- =====================================================
-- 6. RFM SEGMENT SUMMARY
-- Purpose: Summarize customers and revenue by segment
-- =====================================================

CREATE OR REPLACE VIEW rfm_segment_summary AS

SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(AVG(monetary), 2) AS avg_revenue_per_customer

FROM rfm_analysis

GROUP BY segment

ORDER BY total_revenue DESC;

-- =====================================================
-- 7. CATEGORY OPTIONS
-- Purpose: Retrieve unique product categories
-- =====================================================

SELECT DISTINCT
    `Category_Name` AS category

FROM orders

ORDER BY category;

-- =====================================================
-- 8. FILTERED LATE SHIPMENTS
-- Purpose: Retrieve late shipment records for analysis
-- Note: Category filtering can be done using Power BI slicers
-- =====================================================

SELECT
    `Order_Id` AS order_id,
    `Category_Name` AS category,
    `Order_Region` AS region,
    `Shipping_Mode` AS shipping_mode,

    CAST(
        `Days_for_shipping_(real)` AS DECIMAL(10,2)
    ) AS actual_shipping_days,

    CAST(
        `Days_for_shipment_(scheduled)` AS DECIMAL(10,2)
    ) AS scheduled_shipping_days,

    Late_delivery_risk AS late_delivery_risk,

    CAST(Sales AS DECIMAL(12,2)) AS sales,

    ROUND(
        CAST(`Days_for_shipping_(real)` AS DECIMAL(10,2))
        - CAST(`Days_for_shipment_(scheduled)` AS DECIMAL(10,2)),
        2
    ) AS delay_days

FROM orders

WHERE Late_delivery_risk = 1

ORDER BY delay_days DESC

LIMIT 200;
