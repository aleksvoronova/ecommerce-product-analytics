-- E-COMMERCE PRODUCT ANALYTICS
-- PostgreSQL 16
--
-- Cohort:
-- month of customer's first delivered order
--
-- Retention:
-- share of customers from the original cohort
-- who placed at least one delivered order
-- in month N after acquisition
--
-- Customer identity:
-- customer_unique_id


-- 01. DATA COVERAGE CHECK

SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order,
    MIN(order_purchase_timestamp)
        FILTER (WHERE order_status = 'delivered')
        AS first_delivered_order,
    MAX(order_purchase_timestamp)
        FILTER (WHERE order_status = 'delivered')
        AS last_delivered_order
FROM staging.orders;


-- 02. DELIVERED CUSTOMER ORDER MONTHS
--
-- Grain:
-- 1 row = 1 customer active in 1 calendar month
--
-- multiple purchases by the same customer in the same month
-- must count as one active customer.

DROP VIEW IF EXISTS analytics.customer_month_activity CASCADE;

CREATE VIEW analytics.customer_month_activity AS

SELECT DISTINCT
    c.customer_unique_id,

    DATE_TRUNC(
        'month',
        o.order_purchase_timestamp
    )::date AS order_month

FROM staging.orders o

JOIN staging.customers c
    ON o.customer_id = c.customer_id

WHERE
    o.order_status = 'delivered'
    AND o.order_purchase_timestamp IS NOT NULL
    AND c.customer_unique_id IS NOT NULL;


-- 03. CUSTOMER COHORT
--
-- Grain:
-- 1 row = 1 unique customer
--
-- cohort_month = month of first delivered order

DROP VIEW IF EXISTS analytics.customer_cohorts CASCADE;

CREATE VIEW analytics.customer_cohorts AS

SELECT
    customer_unique_id,
    MIN(order_month) AS cohort_month

FROM analytics.customer_month_activity

GROUP BY customer_unique_id;


-- 04. CUSTOMER COHORT ACTIVITY
--
-- Grain:
-- 1 row = 1 customer active in 1 month
--
-- month_number:
-- 0 = acquisition month
-- 1 = next calendar month
-- 2 = two months later
-- ...

DROP VIEW IF EXISTS analytics.customer_cohort_activity CASCADE;

CREATE VIEW analytics.customer_cohort_activity AS

SELECT
    a.customer_unique_id,
    c.cohort_month,
    a.order_month,

    (
        (
            EXTRACT(YEAR FROM a.order_month)::int
            -
            EXTRACT(YEAR FROM c.cohort_month)::int
        ) * 12

        +

        (
            EXTRACT(MONTH FROM a.order_month)::int
            -
            EXTRACT(MONTH FROM c.cohort_month)::int
        )
    ) AS month_number

FROM analytics.customer_month_activity a

JOIN analytics.customer_cohorts c
    ON a.customer_unique_id = c.customer_unique_id;


-- 05. COHORT SIZE
--
-- Grain:
-- 1 row = 1 cohort

DROP VIEW IF EXISTS analytics.cohort_sizes CASCADE;

CREATE VIEW analytics.cohort_sizes AS

SELECT
    cohort_month,
    COUNT(DISTINCT customer_unique_id) AS cohort_size

FROM analytics.customer_cohorts

GROUP BY cohort_month;


-- 06. ACTUAL ACTIVE CUSTOMERS
--
-- Grain:
-- cohort_month + month_number

DROP VIEW IF EXISTS analytics.cohort_activity_counts CASCADE;

CREATE VIEW analytics.cohort_activity_counts AS

SELECT
    cohort_month,
    month_number,

    COUNT(
        DISTINCT customer_unique_id
    ) AS active_customers

FROM analytics.customer_cohort_activity

GROUP BY
    cohort_month,
    month_number;


-- 07. OBSERVATION WINDOW
--
-- Important:
--
-- We need to distinguish:
--
-- 0 customers
--     = the month was observable,
--       but nobody returned
--
-- NULL / absent future month
--     = the dataset does not contain enough future history
--
-- Example:
-- if dataset ends in 2018-08,
-- cohort 2018-08 cannot have Month 1 retention yet.

DROP VIEW IF EXISTS analytics.cohort_observation_spine CASCADE;

CREATE VIEW analytics.cohort_observation_spine AS

WITH dataset_end AS (

    SELECT
        MAX(order_month) AS max_order_month

    FROM analytics.customer_month_activity
),

cohort_horizon AS (

    SELECT
        cs.cohort_month,
        cs.cohort_size,
        de.max_order_month,

        (
            (
                EXTRACT(
                    YEAR FROM de.max_order_month
                )::int

                -

                EXTRACT(
                    YEAR FROM cs.cohort_month
                )::int
            ) * 12

            +

            (
                EXTRACT(
                    MONTH FROM de.max_order_month
                )::int

                -

                EXTRACT(
                    MONTH FROM cs.cohort_month
                )::int
            )
        ) AS max_observable_month

    FROM analytics.cohort_sizes cs

    CROSS JOIN dataset_end de
)

SELECT
    ch.cohort_month,
    ch.cohort_size,
    gs.month_number

FROM cohort_horizon ch

CROSS JOIN LATERAL (

    SELECT
        generate_series(
            0,
            ch.max_observable_month
        ) AS month_number

) gs;


-- 08. FINAL COHORT RETENTION VIEW
--
-- This is the main PA-07 result.
--
-- Grain:
-- cohort_month + month_number

DROP VIEW IF EXISTS analytics.cohort_retention CASCADE;

CREATE VIEW analytics.cohort_retention AS

SELECT
    spine.cohort_month,
    spine.month_number,
    spine.cohort_size,

    COALESCE(
        activity.active_customers,
        0
    ) AS active_customers,

    ROUND(
        100.0
        *
        COALESCE(
            activity.active_customers,
            0
        )
        /
        NULLIF(
            spine.cohort_size,
            0
        ),
        2
    ) AS retention_rate_pct

FROM analytics.cohort_observation_spine spine

LEFT JOIN analytics.cohort_activity_counts activity
    ON spine.cohort_month = activity.cohort_month
    AND spine.month_number = activity.month_number

ORDER BY
    spine.cohort_month,
    spine.month_number;


-- 09. VIEW THE RESULT

SELECT *
FROM analytics.cohort_retention
ORDER BY
    cohort_month,
    month_number;


-- 10. VALIDATION:
-- MONTH 0 MUST BE 100%

SELECT
    cohort_month,
    cohort_size,
    active_customers,
    retention_rate_pct

FROM analytics.cohort_retention

WHERE month_number = 0

ORDER BY cohort_month;


-- 11. VALIDATION:
-- FIND ANY COHORT WHERE MONTH 0 != 100%
--
-- Expected result:
-- 0 rows

SELECT *
FROM analytics.cohort_retention

WHERE
    month_number = 0
    AND retention_rate_pct <> 100.00;


-- 12. RETENTION FOR FIRST 6 MONTHS

SELECT
    cohort_month,
    month_number,
    cohort_size,
    active_customers,
    retention_rate_pct

FROM analytics.cohort_retention

WHERE month_number <= 6

ORDER BY
    cohort_month,
    month_number;


-- 13. AVERAGE RETENTION BY MONTH NUMBER
--
-- Weighted retention:
-- active customers across eligible cohorts /
-- customers across eligible cohorts
--
-- This avoids giving a cohort of 50 customers
-- the same weight as a cohort of 5,000 customers.

SELECT
    month_number,

    SUM(active_customers)
        AS active_customers,

    SUM(cohort_size)
        AS eligible_customers,

    ROUND(
        100.0
        *
        SUM(active_customers)
        /
        NULLIF(
            SUM(cohort_size),
            0
        ),
        2
    ) AS weighted_retention_pct

FROM analytics.cohort_retention

GROUP BY month_number

ORDER BY month_number;


-- 14. COHORT SIZE DISTRIBUTION

SELECT
    cohort_month,
    cohort_size

FROM analytics.cohort_sizes

ORDER BY cohort_month;