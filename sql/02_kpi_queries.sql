-- E-COMMERCE PRODUCT ANALYTICS
-- PostgreSQL 16

-- 01. DATASET OVERVIEW

SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order,
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (
        WHERE order_status = 'delivered'
    ) AS delivered_orders
FROM staging.orders;


-- 02. DELIVERED ORDERS
-- Grain: order

SELECT
    COUNT(*) AS delivered_orders
FROM staging.orders
WHERE order_status = 'delivered';


-- 03. UNIQUE CUSTOMERS
-- customer_unique_id represents a persistent customer identity

SELECT
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers
FROM staging.orders o

JOIN staging.customers c
    ON o.customer_id = c.customer_id

WHERE o.order_status = 'delivered';


-- 04. PRODUCT SALES
-- Sum of item prices, excluding freight

SELECT
    ROUND(
        SUM(oi.price),
        2
    ) AS product_sales

FROM staging.order_items oi

JOIN staging.orders o
    ON oi.order_id = o.order_id

WHERE o.order_status = 'delivered';



-- 05. FREIGHT VALUE

SELECT
    ROUND(
        SUM(oi.freight_value),
        2
    ) AS freight_value

FROM staging.order_items oi

JOIN staging.orders o
    ON oi.order_id = o.order_id

WHERE o.order_status = 'delivered';



-- 06. AVERAGE ORDER VALUE
-- AOV = average product value per delivered order

WITH order_values AS (

    SELECT
        oi.order_id,
        SUM(oi.price) AS order_value

    FROM staging.order_items oi

    JOIN staging.orders o
        ON oi.order_id = o.order_id

    WHERE o.order_status = 'delivered'

    GROUP BY oi.order_id
)

SELECT
    ROUND(
        AVG(order_value),
        2
    ) AS average_order_value

FROM order_values;



-- 07. AVERAGE ITEMS PER ORDER

WITH order_items_count AS (

    SELECT
        oi.order_id,
        COUNT(*) AS items_count

    FROM staging.order_items oi

    JOIN staging.orders o
        ON oi.order_id = o.order_id

    WHERE o.order_status = 'delivered'

    GROUP BY oi.order_id
)

SELECT
    ROUND(
        AVG(items_count),
        2
    ) AS avg_items_per_order

FROM order_items_count;



-- 08. REPEAT CUSTOMER RATE
-- Repeat customer = customer with 2+ delivered orders

WITH customer_orders AS (

    SELECT
        c.customer_unique_id,

        COUNT(
            DISTINCT o.order_id
        ) AS order_count

    FROM staging.orders o

    JOIN staging.customers c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'

    GROUP BY c.customer_unique_id
)

SELECT
    COUNT(*) AS customers,

    COUNT(*) FILTER (
        WHERE order_count > 1
    ) AS repeat_customers,

    ROUND(
        100.0
        *
        COUNT(*) FILTER (
            WHERE order_count > 1
        )
        /
        NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_rate_pct

FROM customer_orders;


-- 09. MONTHLY PRODUCT SALES

SELECT
    DATE_TRUNC(
        'month',
        o.order_purchase_timestamp
    )::date AS month,

    ROUND(
        SUM(oi.price),
        2
    ) AS product_sales

FROM staging.orders o

JOIN staging.order_items oi
    ON o.order_id = oi.order_id

WHERE o.order_status = 'delivered'

GROUP BY 1

ORDER BY 1;


-- 10. MONTHLY ORDERS

SELECT
    DATE_TRUNC(
        'month',
        order_purchase_timestamp
    )::date AS month,

    COUNT(*) AS orders

FROM staging.orders

WHERE order_status = 'delivered'

GROUP BY 1

ORDER BY 1;



-- 11. MONTHLY AOV

WITH order_values AS (

    SELECT
        oi.order_id,
        o.order_purchase_timestamp,
        SUM(oi.price) AS order_value

    FROM staging.order_items oi

    JOIN staging.orders o
        ON oi.order_id = o.order_id

    WHERE o.order_status = 'delivered'

    GROUP BY
        oi.order_id,
        o.order_purchase_timestamp
)

SELECT
    DATE_TRUNC(
        'month',
        order_purchase_timestamp
    )::date AS month,

    ROUND(
        AVG(order_value),
        2
    ) AS average_order_value

FROM order_values

GROUP BY 1

ORDER BY 1;




-- 12. TOP PRODUCT CATEGORIES BY SALES

SELECT
    COALESCE(
        p.product_category_name_english,
        'unknown'
    ) AS category,

    COUNT(*) AS item_rows,

    COUNT(
        DISTINCT oi.order_id
    ) AS orders,

    ROUND(
        SUM(oi.price),
        2
    ) AS product_sales

FROM staging.order_items oi

JOIN staging.orders o
    ON oi.order_id = o.order_id

JOIN staging.products p
    ON oi.product_id = p.product_id

WHERE o.order_status = 'delivered'

GROUP BY 1

ORDER BY product_sales DESC

LIMIT 20;



-- 13. SALES BY CUSTOMER STATE

SELECT
    c.customer_state,

    COUNT(
        DISTINCT o.order_id
    ) AS orders,

    COUNT(
        DISTINCT c.customer_unique_id
    ) AS customers,

    ROUND(
        SUM(oi.price),
        2
    ) AS product_sales

FROM staging.orders o

JOIN staging.customers c
    ON o.customer_id = c.customer_id

JOIN staging.order_items oi
    ON o.order_id = oi.order_id

WHERE o.order_status = 'delivered'

GROUP BY c.customer_state

ORDER BY product_sales DESC;




-- 14. AVERAGE DELIVERY TIME

SELECT
    ROUND(
        AVG(delivery_days)::numeric,
        2
    ) AS avg_delivery_days

FROM staging.orders

WHERE
    order_status = 'delivered'
    AND delivery_days IS NOT NULL;



-- 15. ON-TIME DELIVERY RATE

SELECT
    COUNT(*) AS orders_with_delivery_info,

    COUNT(*) FILTER (
        WHERE delivered_on_time = TRUE
    ) AS on_time_orders,

    COUNT(*) FILTER (
        WHERE delivered_on_time = FALSE
    ) AS late_orders,

    ROUND(
        100.0
        *
        COUNT(*) FILTER (
            WHERE delivered_on_time = TRUE
        )
        /
        NULLIF(COUNT(*), 0),
        2
    ) AS on_time_delivery_rate_pct

FROM staging.orders

WHERE
    order_status = 'delivered'
    AND delivered_on_time IS NOT NULL;



-- 16. AVERAGE REVIEW SCORE
-- First aggregate reviews to order grain

WITH order_reviews AS (

    SELECT
        order_id,
        AVG(review_score) AS order_review_score

    FROM staging.reviews

    GROUP BY order_id
)

SELECT
    ROUND(
        AVG(r.order_review_score)::numeric,
        2
    ) AS avg_review_score

FROM staging.orders o

JOIN order_reviews r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered';



-- 17. DELIVERY PERFORMANCE VS REVIEW SCORE
-- Association only, not causal inference

WITH order_reviews AS (

    SELECT
        order_id,
        AVG(review_score) AS review_score

    FROM staging.reviews

    GROUP BY order_id
)

SELECT

    CASE

        WHEN o.delivered_on_time = TRUE
            THEN 'On time'

        WHEN o.delivered_on_time = FALSE
            THEN 'Late'

        ELSE 'Unknown'

    END AS delivery_status,

    COUNT(*) AS orders,

    ROUND(
        AVG(r.review_score)::numeric,
        2
    ) AS avg_review_score

FROM staging.orders o

JOIN order_reviews r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'

GROUP BY 1

ORDER BY 1;




-- 18. PAYMENT TYPE DISTRIBUTION

SELECT
    p.payment_type,

    COUNT(*) AS payment_records,

    COUNT(
        DISTINCT p.order_id
    ) AS orders_using_type,

    ROUND(
        SUM(p.payment_value),
        2
    ) AS payment_value

FROM staging.payments p

JOIN staging.orders o
    ON p.order_id = o.order_id

WHERE o.order_status = 'delivered'

GROUP BY p.payment_type

ORDER BY payment_value DESC;


-- 19. AVERAGE PAYMENT INSTALLMENTS

SELECT
    payment_type,

    ROUND(
        AVG(payment_installments)::numeric,
        2
    ) AS avg_installments,

    COUNT(*) AS payment_records

FROM staging.payments p

JOIN staging.orders o
    ON p.order_id = o.order_id

WHERE o.order_status = 'delivered'

GROUP BY payment_type

ORDER BY payment_records DESC;



-- 20. ORDER STATUS DISTRIBUTION

SELECT
    order_status,

    COUNT(*) AS orders,

    ROUND(
        100.0 * COUNT(*)
        /
        SUM(COUNT(*)) OVER (),
        2
    ) AS share_pct

FROM staging.orders

GROUP BY order_status

ORDER BY orders DESC;
















