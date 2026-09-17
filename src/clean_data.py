from __future__ import annotations

import pandas as pd


def clean_customers(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очистка таблицы customers.
    Grain: 1 строка = 1 customer_id.
    """

    result = df.copy()

    # Удаляем только полные идентичные строки
    result = result.drop_duplicates().copy()

    # Нормализуем строковые географические признаки
    for col in ["customer_city", "customer_state"]:
        if col in result.columns:
            result[col] = (
                result[col]
                .astype("string")
                .str.strip()
                .str.lower()
            )

    return result


def clean_orders(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очистка таблицы orders.
    Grain: 1 строка = 1 order_id.
    """

    result = df.copy()

    result = result.drop_duplicates().copy()

    # Даты
    date_columns = [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ]

    for col in date_columns:
        if col in result.columns:
            result[col] = pd.to_datetime(
                result[col],
                errors="coerce"
            )

    # Статус заказа
    if "order_status" in result.columns:
        result["order_status"] = (
            result["order_status"]
            .astype("string")
            .str.strip()
            .str.lower()
        )

    # Аналитические признаки
    result["purchase_date"] = (
        result["order_purchase_timestamp"].dt.date
    )

    result["purchase_month"] = (
        result["order_purchase_timestamp"]
        .dt.to_period("M")
        .astype("string")
    )

    result["purchase_year"] = (
        result["order_purchase_timestamp"].dt.year
    )

    result["purchase_month_num"] = (
        result["order_purchase_timestamp"].dt.month
    )

    result["purchase_weekday"] = (
        result["order_purchase_timestamp"].dt.day_name()
    )

    # Продолжительность доставки
    result["delivery_days"] = (
        result["order_delivered_customer_date"]
        - result["order_purchase_timestamp"]
    ).dt.total_seconds() / 86400

    # Отклонение от ожидаемой даты
    result["delay_days"] = (
        result["order_delivered_customer_date"]
        - result["order_estimated_delivery_date"]
    ).dt.total_seconds() / 86400

    # True / False / NA
    result["delivered_on_time"] = pd.Series(
        pd.NA,
        index=result.index,
        dtype="boolean"
    )

    mask = (
        result["order_delivered_customer_date"].notna()
        & result["order_estimated_delivery_date"].notna()
    )

    result.loc[mask, "delivered_on_time"] = (
        result.loc[mask, "order_delivered_customer_date"]
        <= result.loc[mask, "order_estimated_delivery_date"]
    )

    return result


def clean_order_items(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очистка order_items.
    Grain: 1 строка = 1 позиция товара в заказе.
    Ключ: order_id + order_item_id.
    """

    result = df.copy()

    result = result.drop_duplicates().copy()

    if "shipping_limit_date" in result.columns:
        result["shipping_limit_date"] = pd.to_datetime(
            result["shipping_limit_date"],
            errors="coerce"
        )

    for col in ["price", "freight_value"]:
        if col in result.columns:
            result[col] = pd.to_numeric(
                result[col],
                errors="coerce"
            )

    # Стоимость позиции вместе с доставкой.
    # Не путать с revenue по товарам.
    result["item_total"] = (
        result["price"] + result["freight_value"]
    )

    return result


def clean_payments(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очистка payments.
    У одного order_id может быть несколько платежных записей.
    """

    result = df.copy()

    result = result.drop_duplicates().copy()

    for col in [
        "payment_sequential",
        "payment_installments",
        "payment_value"
    ]:
        if col in result.columns:
            result[col] = pd.to_numeric(
                result[col],
                errors="coerce"
            )

    if "payment_type" in result.columns:
        result["payment_type"] = (
            result["payment_type"]
            .astype("string")
            .str.strip()
            .str.lower()
        )

    return result


def clean_reviews(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очистка reviews.

    Пропуски review_comment_title и review_comment_message
    не удаляем: текстовый комментарий является необязательным.
    """

    result = df.copy()

    result = result.drop_duplicates().copy()

    for col in [
        "review_creation_date",
        "review_answer_timestamp"
    ]:
        if col in result.columns:
            result[col] = pd.to_datetime(
                result[col],
                errors="coerce"
            )

    if "review_score" in result.columns:
        result["review_score"] = pd.to_numeric(
            result["review_score"],
            errors="coerce"
        )

    result["has_review_title"] = (
        result["review_comment_title"].notna()
    )

    result["has_review_comment"] = (
        result["review_comment_message"].notna()
    )

    return result


def clean_products(
    products: pd.DataFrame,
    categories: pd.DataFrame
) -> pd.DataFrame:
    """
    Очистка products и добавление английского названия категории.
    """

    result = products.copy()
    category_map = categories.copy()

    result = result.drop_duplicates().copy()
    category_map = category_map.drop_duplicates().copy()

    numeric_columns = [
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ]

    for col in numeric_columns:
        if col in result.columns:
            result[col] = pd.to_numeric(
                result[col],
                errors="coerce"
            )

    result = result.merge(
        category_map,
        how="left",
        on="product_category_name",
        validate="m:1"
    )

    result["product_category_name"] = (
        result["product_category_name"]
        .fillna("unknown")
    )

    result["product_category_name_english"] = (
        result["product_category_name_english"]
        .fillna("unknown")
    )

    return result


def clean_sellers(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очистка sellers.
    """

    result = df.copy()

    result = result.drop_duplicates().copy()

    for col in ["seller_city", "seller_state"]:
        if col in result.columns:
            result[col] = (
                result[col]
                .astype("string")
                .str.strip()
                .str.lower()
            )

    return result


def clean_geolocation(
    df: pd.DataFrame
) -> pd.DataFrame:
    """
    Удаляем только полные идентичные строки geolocation.

    НЕ удаляем строки только по geolocation_zip_code_prefix,
    так как одному prefix могут соответствовать несколько координат.
    """

    result = df.copy()

    result = result.drop_duplicates().copy()

    for col in [
        "geolocation_city",
        "geolocation_state"
    ]:
        if col in result.columns:
            result[col] = (
                result[col]
                .astype("string")
                .str.strip()
                .str.lower()
            )

    return result