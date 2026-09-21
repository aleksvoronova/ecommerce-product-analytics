
-- E-COMMERCE PRODUCT ANALYTICS

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;

-- CLEAN RECREATE

DROP TABLE IF EXISTS staging.reviews CASCADE;
DROP TABLE IF EXISTS staging.payments CASCADE;
DROP TABLE IF EXISTS staging.order_items CASCADE;
DROP TABLE IF EXISTS staging.orders CASCADE;
DROP TABLE IF EXISTS staging.geolocation CASCADE;
DROP TABLE IF EXISTS staging.products CASCADE;
DROP TABLE IF EXISTS staging.sellers CASCADE;
DROP TABLE IF EXISTS staging.customers CASCADE;

-- CUSTOMERS

CREATE TABLE staging.customers (
    customer_id              TEXT PRIMARY KEY,
    customer_unique_id       TEXT NOT NULL,
    customer_zip_code_prefix INTEGER,
    customer_city            TEXT,
    customer_state           TEXT
);


-- PRODUCTS

CREATE TABLE staging.products (
    product_id                     TEXT PRIMARY KEY,
    product_category_name          TEXT,
    product_name_lenght            DOUBLE PRECISION,
    product_description_lenght     DOUBLE PRECISION,
    product_photos_qty             DOUBLE PRECISION,
    product_weight_g               DOUBLE PRECISION,
    product_length_cm              DOUBLE PRECISION,
    product_height_cm              DOUBLE PRECISION,
    product_width_cm               DOUBLE PRECISION,
    product_category_name_english  TEXT
);


-- SELLERS

CREATE TABLE staging.sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix INTEGER,
    seller_city            TEXT,
    seller_state           TEXT
);


-- ORDERS

CREATE TABLE staging.orders (
    order_id                       TEXT PRIMARY KEY,
    customer_id                    TEXT NOT NULL,
    order_status                   TEXT,
    order_purchase_timestamp       TIMESTAMP,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP,

    purchase_date                  DATE,
    purchase_month                 TEXT,
    purchase_year                  INTEGER,
    purchase_month_num             INTEGER,
    purchase_weekday               TEXT,

    delivery_days                  DOUBLE PRECISION,
    delay_days                     DOUBLE PRECISION,
    delivered_on_time              BOOLEAN,

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES staging.customers(customer_id)
);


-- ORDER ITEMS

CREATE TABLE staging.order_items (
    order_id             TEXT NOT NULL,
    order_item_id        INTEGER NOT NULL,
    product_id           TEXT NOT NULL,
    seller_id            TEXT NOT NULL,
    shipping_limit_date  TIMESTAMP,
    price                 NUMERIC(14, 2),
    freight_value         NUMERIC(14, 2),
    item_total            NUMERIC(14, 2),

    PRIMARY KEY (
        order_id,
        order_item_id
    ),

    CONSTRAINT fk_items_order
        FOREIGN KEY (order_id)
        REFERENCES staging.orders(order_id),

    CONSTRAINT fk_items_product
        FOREIGN KEY (product_id)
        REFERENCES staging.products(product_id),

    CONSTRAINT fk_items_seller
        FOREIGN KEY (seller_id)
        REFERENCES staging.sellers(seller_id)
);


-- PAYMENTS

CREATE TABLE staging.payments (
    order_id              TEXT NOT NULL,
    payment_sequential    INTEGER NOT NULL,
    payment_type          TEXT,
    payment_installments  INTEGER,
    payment_value         NUMERIC(14, 2),

    PRIMARY KEY (
        order_id,
        payment_sequential
    ),

    CONSTRAINT fk_payments_order
        FOREIGN KEY (order_id)
        REFERENCES staging.orders(order_id)
);


-- REVIEWS

CREATE TABLE staging.reviews (
    review_row_id            BIGSERIAL PRIMARY KEY,
    review_id                TEXT,
    order_id                 TEXT NOT NULL,
    review_score             INTEGER,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP,
    has_review_title         BOOLEAN,
    has_review_comment       BOOLEAN,

    CONSTRAINT fk_reviews_order
        FOREIGN KEY (order_id)
        REFERENCES staging.orders(order_id)
);


-- GEOLOCATION

CREATE TABLE staging.geolocation (
    geolocation_row_id          BIGSERIAL PRIMARY KEY,
    geolocation_zip_code_prefix INTEGER,
    geolocation_lat             DOUBLE PRECISION,
    geolocation_lng             DOUBLE PRECISION,
    geolocation_city            TEXT,
    geolocation_state           TEXT
);


-- INDEXES

CREATE INDEX idx_customers_unique_id
    ON staging.customers(customer_unique_id);

CREATE INDEX idx_orders_customer_id
    ON staging.orders(customer_id);

CREATE INDEX idx_orders_purchase_timestamp
    ON staging.orders(order_purchase_timestamp);

CREATE INDEX idx_orders_status
    ON staging.orders(order_status);

CREATE INDEX idx_items_product
    ON staging.order_items(product_id);

CREATE INDEX idx_items_seller
    ON staging.order_items(seller_id);

CREATE INDEX idx_payments_order
    ON staging.payments(order_id);

CREATE INDEX idx_reviews_order
    ON staging.reviews(order_id);

CREATE INDEX idx_geolocation_zip
    ON staging.geolocation(geolocation_zip_code_prefix);