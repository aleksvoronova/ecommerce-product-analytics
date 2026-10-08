-- E-COMMERCE PRODUCT ANALYTICS
-- PostgreSQL 16

-- MODEL:

-- Dimensions:
--   dim_date
--   dim_customers
--   dim_products
--   dim_sellers

-- Facts:
--   fact_orders
--   fact_order_items
--   fact_payments

-- Analytical table:
--   cohort_retention (created in PA-07)


-- CLEAN RECREATE

DROP VIEW IF EXISTS analytics.fact_payments CASCADE;
DROP VIEW IF EXISTS analytics.fact_order_items CASCADE;
DROP VIEW IF EXISTS analytics.fact_orders CASCADE;

DROP VIEW IF EXISTS analytics.dim_sellers CASCADE;
DROP VIEW IF EXISTS analytics.dim_products CASCADE;
DROP VIEW IF EXISTS analytics.dim_customers CASCADE;
DROP VIEW IF EXISTS analytics.dim_date CASCADE;


-- 01. DATE DIMENSION
-- Grain:
-- 1 row = 1 calendar date

CREATE VIEW analytics.dim_date AS

WITH bounds AS (

    SELECT
        MIN(order_purchase_timestamp)::date AS min_date,
        MAX(order_purchase_timestamp)::date AS max_date

    FROM staging.orders

),

calendar AS (

    SELECT
        generate_series(
            min_date,
            max_date,
            INTERVAL '1 day'
        )::date AS date_key

    FROM bounds

)

SELECT
    date_key,

    EXTRACT(YEAR FROM date_key)::int
        AS year,

    EXTRACT(QUARTER FROM date_key)::int
        AS quarter,

    EXTRACT(MONTH FROM date_key)::int
        AS month_number,

    TO_CHAR(date_key, 'FMMonth')
        AS month_name,

    DATE_TRUNC(
        'month',
        date_key
    )::date AS month_start,

    TO_CHAR(
        date_key,
        'YYYY-MM'
    ) AS year_month,

    (
        EXTRACT(YEAR FROM date_key)::int * 100
        +
        EXTRACT(MONTH FROM date_key)::int
    ) AS year_month_sort,

    DATE_TRUNC(
        'week',
        date_key
    )::date AS week_start,

    EXTRACT(
        ISODOW FROM date_key
    )::int AS day_of_week_number,

    TO_CHAR(
        date_key,
        'FMDay'
    ) AS day_name,

    CASE
        WHEN EXTRACT(ISODOW FROM date_key) IN (6, 7)
            THEN TRUE
        ELSE FALSE
    END AS is_weekend

FROM calendar;



-- 02. CUSTOMER DIMENSION

-- Grain:
-- 1 row = 1 customer_unique_id

-- Customer location:
-- latest known customer record

-- RFM and cohort attributes are added to the dimension.

CREATE VIEW analytics.dim_customers AS

WITH customer_history AS (

    SELECT
        c.customer_unique_id,
        c.customer_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,

        o.order_purchase_timestamp,

        ROW_NUMBER() OVER (

            PARTITION BY
                c.customer_unique_id

            ORDER BY
                o.order_purchase_timestamp DESC NULLS LAST,
                c.customer_id DESC

        ) AS rn

    FROM staging.customers c

    LEFT JOIN staging.orders o
        ON c.customer_id = o.customer_id

)

SELECT
    ch.customer_unique_id,

    ch.customer_zip_code_prefix,

    ch.customer_city,

    ch.customer_state,

    cohort.cohort_month,

    rfm.last_purchase_date,

    rfm.recency_days,

    rfm.frequency,

    rfm.monetary,

    rfm.avg_order_value,

    rfm.r_score,

    rfm.f_score,

    rfm.m_score,

    rfm.rfm_code,

    rfm.segment AS rfm_segment

FROM customer_history ch

LEFT JOIN analytics.customer_cohorts cohort
    ON ch.customer_unique_id =
       cohort.customer_unique_id

LEFT JOIN analytics.rfm_segments rfm
    ON ch.customer_unique_id =
       rfm.customer_unique_id

WHERE ch.rn = 1;



-- 03. PRODUCT DIMENSION
-- Grain:
-- 1 row = 1 product

CREATE VIEW analytics.dim_products AS

SELECT
    product_id,

    product_category_name,

    product_category_name_english,

    product_name_lenght,

    product_description_lenght,

    product_photos_qty,

    product_weight_g,

    product_length_cm,

    product_height_cm,

    product_width_cm

FROM staging.products;



-- 04. SELLER DIMENSION
-- Grain:
-- 1 row = 1 seller


CREATE VIEW analytics.dim_sellers AS

SELECT
    seller_id,

    seller_zip_code_prefix,

    seller_city,

    seller_state

FROM staging.sellers;



-- 05. ORDER FACT

-- Grain:
-- 1 row = 1 order

-- Used for:
-- orders
-- customers
-- delivery
-- review
-- order-level value
-- payment totals

CREATE VIEW analytics.fact_orders AS

WITH item_agg AS (

    SELECT
        order_id,

        COUNT(*) AS item_count,

        COUNT(
            DISTINCT product_id
        ) AS distinct_products,

        COUNT(
            DISTINCT seller_id
        ) AS distinct_sellers,

        ROUND(
            SUM(price),
            2
        ) AS product_sales,

        ROUND(
            SUM(freight_value),
            2
        ) AS freight_value

    FROM staging.order_items

    GROUP BY order_id
),

payment_agg AS (

    SELECT
        order_id,

        COUNT(*) AS payment_records,

        ROUND(
            SUM(payment_value),
            2
        ) AS payment_value,

        MAX(payment_installments)
            AS max_installments

    FROM staging.payments

    GROUP BY order_id
),

review_agg AS (

    SELECT
        order_id,

        COUNT(*) AS review_count,

        ROUND(
            AVG(review_score)::numeric,
            2
        ) AS avg_review_score

    FROM staging.reviews

    GROUP BY order_id
)

SELECT
    o.order_id,

    o.customer_id,

    c.customer_unique_id,

    o.order_status,

    o.order_purchase_timestamp,

    o.order_purchase_timestamp::date
        AS purchase_date,

    o.order_approved_at,

    o.order_delivered_carrier_date,

    o.order_delivered_customer_date,

    o.order_estimated_delivery_date,

    o.delivery_days,

    o.delay_days,

    o.delivered_on_time,

    COALESCE(
        ia.item_count,
        0
    ) AS item_count,

    COALESCE(
        ia.distinct_products,
        0
    ) AS distinct_products,

    COALESCE(
        ia.distinct_sellers,
        0
    ) AS distinct_sellers,

    COALESCE(
        ia.product_sales,
        0
    ) AS product_sales,

    COALESCE(
        ia.freight_value,
        0
    ) AS freight_value,

    ROUND(
        COALESCE(ia.product_sales, 0)
        +
        COALESCE(ia.freight_value, 0),
        2
    ) AS product_plus_freight,

    COALESCE(
        pa.payment_records,
        0
    ) AS payment_records,

    COALESCE(
        pa.payment_value,
        0
    ) AS payment_value,

    pa.max_installments,

    COALESCE(
        ra.review_count,
        0
    ) AS review_count,

    ra.avg_review_score

FROM staging.orders o

JOIN staging.customers c
    ON o.customer_id = c.customer_id

LEFT JOIN item_agg ia
    ON o.order_id = ia.order_id

LEFT JOIN payment_agg pa
    ON o.order_id = pa.order_id

LEFT JOIN review_agg ra
    ON o.order_id = ra.order_id;



-- 06. ORDER ITEM FACT

-- Grain:
-- 1 row = 1 item within an order

-- Used for:
-- products
-- categories
-- sellers
-- product sales
-- freight


CREATE VIEW analytics.fact_order_items AS

SELECT
    oi.order_id,

    oi.order_item_id,

    oi.product_id,

    oi.seller_id,

    c.customer_unique_id,

    o.order_purchase_timestamp::date
        AS purchase_date,

    o.order_status,

    oi.shipping_limit_date,

    oi.price,

    oi.freight_value,

    oi.item_total

FROM staging.order_items oi

JOIN staging.orders o
    ON oi.order_id = o.order_id

JOIN staging.customers c
    ON o.customer_id = c.customer_id;



-- 07. PAYMENT FACT

-- Grain:
-- 1 row = 1 payment record

-- Used for:
-- payment type
-- installments
-- payment value

CREATE VIEW analytics.fact_payments AS

SELECT
    p.order_id,

    p.payment_sequential,

    c.customer_unique_id,

    o.order_purchase_timestamp::date
        AS purchase_date,

    o.order_status,

    p.payment_type,

    p.payment_installments,

    p.payment_value

FROM staging.payments p

JOIN staging.orders o
    ON p.order_id = o.order_id

JOIN staging.customers c
    ON o.customer_id = c.customer_id;



-- 08. MODEL VALIDATION

SELECT
    'dim_date' AS object_name,
    COUNT(*) AS rows
FROM analytics.dim_date

UNION ALL

SELECT
    'dim_customers',
    COUNT(*)
FROM analytics.dim_customers

UNION ALL

SELECT
    'dim_products',
    COUNT(*)
FROM analytics.dim_products

UNION ALL

SELECT
    'dim_sellers',
    COUNT(*)
FROM analytics.dim_sellers

UNION ALL

SELECT
    'fact_orders',
    COUNT(*)
FROM analytics.fact_orders

UNION ALL

SELECT
    'fact_order_items',
    COUNT(*)
FROM analytics.fact_order_items

UNION ALL

SELECT
    'fact_payments',
    COUNT(*)
FROM analytics.fact_payments

ORDER BY object_name;



-- 09. FACT ORDER GRAIN CHECK

-- Expected:
-- rows = unique_orders


SELECT
    COUNT(*) AS rows,

    COUNT(
        DISTINCT order_id
    ) AS unique_orders

FROM analytics.fact_orders;



-- 10. ORDER ITEM GRAIN CHECK

-- Expected:
-- rows = unique order/item combinations


SELECT
    COUNT(*) AS rows,

    COUNT(
        DISTINCT
        (order_id, order_item_id)
    ) AS unique_order_items

FROM analytics.fact_order_items;



-- 11. CUSTOMER DIMENSION GRAIN CHECK

-- Expected:
-- rows = unique_customers

SELECT
    COUNT(*) AS rows,

    COUNT(
        DISTINCT customer_unique_id
    ) AS unique_customers

FROM analytics.dim_customers;



-- 12. PRODUCT DIMENSION GRAIN CHECK


SELECT
    COUNT(*) AS rows,

    COUNT(
        DISTINCT product_id
    ) AS unique_products

FROM analytics.dim_products;



-- 13. SELLER DIMENSION GRAIN CHECK

SELECT
    COUNT(*) AS rows,

    COUNT(
        DISTINCT seller_id
    ) AS unique_sellers

FROM analytics.dim_sellers;