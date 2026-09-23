-- E-COMMERCE PRODUCT ANALYTICS
-- PostgreSQL 16
--
-- R = Recency
--     Days since customer's last delivered purchase
--
-- F = Frequency
--     Number of delivered orders
--
-- M = Monetary
--     Total product sales (excluding freight)
--
-- Customer identity:
-- customer_unique_id
--


-- CLEAN RECREATE

DROP VIEW IF EXISTS analytics.rfm_segment_summary CASCADE;
DROP VIEW IF EXISTS analytics.rfm_segments CASCADE;
DROP VIEW IF EXISTS analytics.rfm_customer_scores CASCADE;
DROP VIEW IF EXISTS analytics.rfm_thresholds CASCADE;
DROP VIEW IF EXISTS analytics.rfm_customer_metrics CASCADE;
DROP VIEW IF EXISTS analytics.customer_order_values CASCADE;
DROP VIEW IF EXISTS analytics.rfm_reference_date CASCADE;


-- 01. REFERENCE DATE
--
-- Dataset is historical.
-- Do NOT use CURRENT_DATE.
--
-- Reference date =
-- last delivered purchase date + 1 day

CREATE VIEW analytics.rfm_reference_date AS

SELECT
    (
        MAX(order_purchase_timestamp)::date
        + 1
    ) AS reference_date

FROM staging.orders

WHERE
    order_status = 'delivered'
    AND order_purchase_timestamp IS NOT NULL;


-- Check
SELECT *
FROM analytics.rfm_reference_date;


-- 02. ORDER-LEVEL VALUE
--
-- Grain:
-- 1 row = 1 delivered order
--
-- We aggregate order_items BEFORE customer-level RFM
-- This protects the analysis from row multiplication

CREATE VIEW analytics.customer_order_values AS

SELECT
    o.order_id,

    c.customer_unique_id,

    o.order_purchase_timestamp::date
        AS purchase_date,

    ROUND(
        SUM(oi.price),
        2
    ) AS order_value,

    ROUND(
        SUM(oi.freight_value),
        2
    ) AS freight_value,

    COUNT(*) AS item_count

FROM staging.orders o

JOIN staging.customers c
    ON o.customer_id = c.customer_id

JOIN staging.order_items oi
    ON o.order_id = oi.order_id

WHERE
    o.order_status = 'delivered'
    AND c.customer_unique_id IS NOT NULL

GROUP BY
    o.order_id,
    c.customer_unique_id,
    o.order_purchase_timestamp;


-- 03. RFM CUSTOMER METRICS
--
-- Grain:
-- 1 row = 1 customer_unique_id

CREATE VIEW analytics.rfm_customer_metrics AS

SELECT
    ov.customer_unique_id,

    MAX(
        ov.purchase_date
    ) AS last_purchase_date,

    (
        ref.reference_date
        -
        MAX(ov.purchase_date)
    ) AS recency_days,

    COUNT(
        DISTINCT ov.order_id
    ) AS frequency,

    ROUND(
        SUM(ov.order_value),
        2
    ) AS monetary,

    ROUND(
        AVG(ov.order_value),
        2
    ) AS avg_order_value

FROM analytics.customer_order_values ov

CROSS JOIN analytics.rfm_reference_date ref

GROUP BY
    ov.customer_unique_id,
    ref.reference_date;



-- 04. BASIC CHECK


SELECT *
FROM analytics.rfm_customer_metrics
ORDER BY monetary DESC
LIMIT 20;



-- 05. RFM METRIC DISTRIBUTION


SELECT
    COUNT(*) AS customers,

    MIN(recency_days) AS min_recency,
    ROUND(
        AVG(recency_days),
        2
    ) AS avg_recency,
    MAX(recency_days) AS max_recency,

    MIN(frequency) AS min_frequency,
    ROUND(
        AVG(frequency),
        2
    ) AS avg_frequency,
    MAX(frequency) AS max_frequency,

    ROUND(
        MIN(monetary),
        2
    ) AS min_monetary,

    ROUND(
        AVG(monetary),
        2
    ) AS avg_monetary,

    ROUND(
        MAX(monetary),
        2
    ) AS max_monetary

FROM analytics.rfm_customer_metrics;



-- 06. FREQUENCY DISTRIBUTION
--
-- Important for Olist because frequency is highly skewed.


SELECT
    frequency,
    COUNT(*) AS customers,

    ROUND(
        100.0
        * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_share_pct

FROM analytics.rfm_customer_metrics

GROUP BY frequency

ORDER BY frequency;



-- 07. RECENCY + MONETARY THRESHOLDS
--
-- We use distribution-based quintile thresholds for:
--
-- Recency
-- Monetary
--
-- Frequency is discrete and highly skewed,
-- therefore it is scored separately.


CREATE VIEW analytics.rfm_thresholds AS

SELECT

    PERCENTILE_CONT(0.20)
        WITHIN GROUP (
            ORDER BY recency_days
        ) AS recency_p20,

    PERCENTILE_CONT(0.40)
        WITHIN GROUP (
            ORDER BY recency_days
        ) AS recency_p40,

    PERCENTILE_CONT(0.60)
        WITHIN GROUP (
            ORDER BY recency_days
        ) AS recency_p60,

    PERCENTILE_CONT(0.80)
        WITHIN GROUP (
            ORDER BY recency_days
        ) AS recency_p80,


    PERCENTILE_CONT(0.20)
        WITHIN GROUP (
            ORDER BY monetary
        ) AS monetary_p20,

    PERCENTILE_CONT(0.40)
        WITHIN GROUP (
            ORDER BY monetary
        ) AS monetary_p40,

    PERCENTILE_CONT(0.60)
        WITHIN GROUP (
            ORDER BY monetary
        ) AS monetary_p60,

    PERCENTILE_CONT(0.80)
        WITHIN GROUP (
            ORDER BY monetary
        ) AS monetary_p80

FROM analytics.rfm_customer_metrics;


-- Inspect thresholds
SELECT *
FROM analytics.rfm_thresholds;



-- 08. RFM SCORES
--
-- Recency:
-- lower is better
--
-- Monetary:
-- higher is better
--
-- Frequency:
-- 1 order  -> 1
-- 2 orders -> 3
-- 3 orders -> 4
-- 4+       -> 5
--
-- This avoids arbitrary NTILE splitting of customers
-- with identical frequency values.


CREATE VIEW analytics.rfm_customer_scores AS

SELECT
    rfm.*,


    -- RECENCY SCORE

    CASE

        WHEN rfm.recency_days
             <= t.recency_p20
            THEN 5

        WHEN rfm.recency_days
             <= t.recency_p40
            THEN 4

        WHEN rfm.recency_days
             <= t.recency_p60
            THEN 3

        WHEN rfm.recency_days
             <= t.recency_p80
            THEN 2

        ELSE 1

    END AS r_score,



    -- FREQUENCY SCORE


    CASE

        WHEN rfm.frequency >= 4
            THEN 5

        WHEN rfm.frequency = 3
            THEN 4

        WHEN rfm.frequency = 2
            THEN 3

        ELSE 1

    END AS f_score,



    -- MONETARY SCORE


    CASE

        WHEN rfm.monetary
             <= t.monetary_p20
            THEN 1

        WHEN rfm.monetary
             <= t.monetary_p40
            THEN 2

        WHEN rfm.monetary
             <= t.monetary_p60
            THEN 3

        WHEN rfm.monetary
             <= t.monetary_p80
            THEN 4

        ELSE 5

    END AS m_score


FROM analytics.rfm_customer_metrics rfm

CROSS JOIN analytics.rfm_thresholds t;



-- 09. FINAL RFM SEGMENTS


CREATE VIEW analytics.rfm_segments AS

SELECT
    *,

    CONCAT(
        r_score,
        f_score,
        m_score
    ) AS rfm_code,


    CASE


        -- CHAMPIONS
        -- Recent + repeat + high value


        WHEN
            r_score >= 4
            AND f_score >= 3
            AND m_score >= 4

        THEN 'Champions'



        -- LOYAL CUSTOMERS
        -- Repeat customers who are still relatively recent


        WHEN
            r_score >= 3
            AND f_score >= 3

        THEN 'Loyal Customers'



        -- AT RISK
        -- Previously repeat customers,
        -- but they have not purchased recently

        WHEN
            r_score <= 2
            AND f_score >= 3

        THEN 'At Risk'



        -- RECENT CUSTOMERS
        -- Very recent first-time / single-order customers


        WHEN
            r_score = 5
            AND f_score = 1
            AND m_score < 3

        THEN 'Recent Customers'


        -- POTENTIAL LOYALISTS
        -- Recent single-order customers with
        -- medium/high monetary value


        WHEN
            r_score >= 4
            AND f_score = 1
            AND m_score >= 3

        THEN 'Potential Loyalists'



        -- LOST CUSTOMERS
        -- Old single-order customers


        WHEN
            r_score <= 2
            AND f_score = 1

        THEN 'Lost Customers'


        -- OTHER

        ELSE 'Other'

    END AS segment


FROM analytics.rfm_customer_scores;



-- 10. INSPECT CUSTOMER SEGMENTS


SELECT *
FROM analytics.rfm_segments

ORDER BY
    segment,
    monetary DESC

LIMIT 100;



-- 11. SEGMENT SUMMARY


CREATE VIEW analytics.rfm_segment_summary AS

SELECT
    segment,

    COUNT(*) AS customers,

    ROUND(
        100.0
        * COUNT(*)
        /
        SUM(COUNT(*)) OVER (),
        2
    ) AS customer_share_pct,

    ROUND(
        SUM(monetary),
        2
    ) AS product_sales,

    ROUND(
        100.0
        * SUM(monetary)
        /
        SUM(SUM(monetary)) OVER (),
        2
    ) AS product_sales_share_pct,

    ROUND(
        AVG(monetary),
        2
    ) AS avg_customer_value,

    ROUND(
        AVG(frequency),
        2
    ) AS avg_frequency,

    ROUND(
        AVG(recency_days),
        2
    ) AS avg_recency_days

FROM analytics.rfm_segments

GROUP BY segment

ORDER BY product_sales DESC;



-- 12. VIEW SEGMENT SUMMARY


SELECT *
FROM analytics.rfm_segment_summary;



-- 13. VALIDATION:
-- NO INVALID RFM VALUES
--
-- Expected:
-- 0 rows


SELECT *
FROM analytics.rfm_customer_metrics

WHERE
    recency_days < 0
    OR frequency < 1
    OR monetary < 0;



-- 14. VALIDATION:
-- SCORES MUST BE WITHIN 1..5
--
-- Expected:
-- 0 rows


SELECT *
FROM analytics.rfm_customer_scores

WHERE
    r_score NOT BETWEEN 1 AND 5
    OR f_score NOT BETWEEN 1 AND 5
    OR m_score NOT BETWEEN 1 AND 5;



-- 15. VALIDATION:
-- EVERY CUSTOMER MUST HAVE A SEGMENT
--
-- Expected:
-- 0 rows


SELECT *
FROM analytics.rfm_segments
WHERE segment IS NULL;



-- 16. VALIDATION:
-- CUSTOMER COUNT


SELECT
    (
        SELECT
            COUNT(DISTINCT c.customer_unique_id)

        FROM staging.orders o

        JOIN staging.customers c
            ON o.customer_id = c.customer_id

        WHERE o.order_status = 'delivered'
    ) AS expected_customers,


    (
        SELECT
            COUNT(*)

        FROM analytics.rfm_segments
    ) AS rfm_customers;



-- 17. NUMBER OF REPEAT CUSTOMERS


SELECT
    COUNT(*) AS repeat_customers,

    ROUND(
        100.0
        * COUNT(*)
        /
        (
            SELECT COUNT(*)
            FROM analytics.rfm_segments
        ),
        2
    ) AS repeat_customer_share_pct

FROM analytics.rfm_segments

WHERE frequency >= 2;