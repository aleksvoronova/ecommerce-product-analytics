from pathlib import Path
import os

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


# Paths

BASE_DIR = Path(__file__).resolve().parents[1]

PROCESSED_DIR = BASE_DIR / "data" / "processed"

SCHEMA_SQL_PATH = BASE_DIR / "sql" / "01_schema.sql"

ENV_PATH = BASE_DIR / ".env"

# Environment variables

load_dotenv(ENV_PATH)

REQUIRED_ENV_VARS = [
    "DB_HOST",
    "DB_PORT",
    "DB_NAME",
    "DB_USER",
    "DB_PASSWORD",
]

missing_env_vars = [
    var
    for var in REQUIRED_ENV_VARS
    if not os.getenv(var)
]

if missing_env_vars:
    raise RuntimeError(
        "Variables in .env are not filled out в .env: "
        + ", ".join(missing_env_vars)
    )


# Database connection

database_url = URL.create(
    drivername="postgresql+psycopg2",
    username=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    host=os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT")),
    database=os.getenv("DB_NAME"),
)

engine = create_engine(
    database_url,
    pool_pre_ping=True,
)


# Table configuration


TABLE_CONFIG = {
    "customers": {
        "file": "customers.csv",
        "parse_dates": [],
        "boolean_columns": [],
    },

    "products": {
        "file": "products.csv",
        "parse_dates": [],
        "boolean_columns": [],
    },

    "sellers": {
        "file": "sellers.csv",
        "parse_dates": [],
        "boolean_columns": [],
    },

    "orders": {
        "file": "orders.csv",
        "parse_dates": [
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
            "purchase_date",
        ],
        "boolean_columns": [
            "delivered_on_time",
        ],
    },

    "order_items": {
        "file": "order_items.csv",
        "parse_dates": [
            "shipping_limit_date",
        ],
        "boolean_columns": [],
    },

    "payments": {
        "file": "payments.csv",
        "parse_dates": [],
        "boolean_columns": [],
    },

    "reviews": {
        "file": "reviews.csv",
        "parse_dates": [
            "review_creation_date",
            "review_answer_timestamp",
        ],
        "boolean_columns": [
            "has_review_title",
            "has_review_comment",
        ],
    },

    "geolocation": {
        "file": "geolocation.csv",
        "parse_dates": [],
        "boolean_columns": [],
    },
}


# Connection test


def test_connection():


    with engine.connect() as connection:

        version = connection.execute(
            text("SELECT version();")
        ).scalar()

        current_database = connection.execute(
            text("SELECT current_database();")
        ).scalar()

    print("PostgreSQL connection successful")
    print(f"Database: {current_database}")
    print(version)


# BOOLEAN CONVERSION

def convert_boolean_column(df, column):

    if column not in df.columns:
        return df

    mapping = {
        True: True,
        False: False,

        "True": True,
        "False": False,

        "true": True,
        "false": False,

        "TRUE": True,
        "FALSE": False,

        "1": True,
        "0": False,

        1: True,
        0: False,
    }

    df[column] = (
        df[column]
        .map(mapping)
        .astype("boolean")
    )

    return df


# Read CSV


def read_processed_table(table_name, config):


    file_path = PROCESSED_DIR / config["file"]

    if not file_path.exists():

        if table_name == "geolocation":
            print(
                " geolocation.csv is not found "
                "Table geolocation will be skipped"
            )

            return None

        raise FileNotFoundError(
            f"Processed-файл is not found:\n{file_path}"
        )

    df = pd.read_csv(
        file_path,
        parse_dates=config["parse_dates"],
    )

    for column in config["boolean_columns"]:

        df = convert_boolean_column(
            df,
            column,
        )

    # PostgreSQL DATE instead of TIMESTAMP
    if (
        table_name == "orders"
        and "purchase_date" in df.columns
    ):

        df["purchase_date"] = (
            pd.to_datetime(
                df["purchase_date"],
                errors="coerce",
            )
            .dt.date
        )

    return df


# Check precessed files


def validate_processed_files():


    print("\nProcessed-files check")
    print("-" * 70)

    missing = []

    for table_name, config in TABLE_CONFIG.items():

        file_path = (
            PROCESSED_DIR
            / config["file"]
        )

        if file_path.exists():

            print(
                f"✓ {config['file']}"
            )

        elif table_name == "geolocation":

            print(
                f" {config['file']} is missing "
                "(optional)"
            )

        else:

            print(
                f"✗ {config['file']}"
            )

            missing.append(
                config["file"]
            )

    if missing:

        raise FileNotFoundError(
            "\nMandatory processed-files are missing:\n"
            + "\n".join(
                f"- {file}"
                for file in missing
            )
        )


# Recreate schema


def recreate_schema():


    if not SCHEMA_SQL_PATH.exists():

        raise FileNotFoundError(
            f"SQL schema file not found:\n"
            f"{SCHEMA_SQL_PATH}"
        )

    sql_script = SCHEMA_SQL_PATH.read_text(
        encoding="utf-8"
    )

    raw_connection = engine.raw_connection()

    try:

        cursor = raw_connection.cursor()

        cursor.execute(
            sql_script
        )

        raw_connection.commit()

        cursor.close()

    except Exception:

        raw_connection.rollback()

        raise

    finally:

        raw_connection.close()

    print(
        "\n Schemas and PostgreSQL tables are recreated"
    )

# Load one table

def load_table(table_name, config):


    df = read_processed_table(
        table_name,
        config,
    )

    if df is None:
        return None

    print(
        f"\n{table_name}"
    )

    print(
        f"  CSV rows: {len(df):,}"
    )

    df.to_sql(
        name=table_name,
        con=engine,
        schema="staging",
        if_exists="append",
        index=False,
        chunksize=1000,
        method="multi",
    )

    print(
        f"   staging.{table_name}"
    )

    return len(df)


# Load all tables


def load_all_tables():


    print("\n" + "=" * 70)
    print("POSTGRESQL DATA LOAD")
    print("=" * 70)

    loaded_counts = {}

    # The order is critical - FK
    load_order = [
        "customers",
        "products",
        "sellers",
        "orders",
        "order_items",
        "payments",
        "reviews",
        "geolocation",
    ]

    for table_name in load_order:

        rows = load_table(
            table_name,
            TABLE_CONFIG[table_name],
        )

        if rows is not None:

            loaded_counts[
                table_name
            ] = rows

    return loaded_counts


# Database row counts

def get_database_counts():


    counts = {}

    with engine.connect() as connection:

        for table_name in TABLE_CONFIG:

            result = connection.execute(
                text(
                    f"""
                    SELECT COUNT(*)
                    FROM staging.{table_name}
                    """
                )
            )

            counts[table_name] = (
                result.scalar()
            )

    return counts



# Validation


def validate_row_counts(
    csv_counts,
    database_counts,
):
    """
    Compares CSV and PostgreSQL
    """

    print("\n" + "=" * 70)
    print("ROW COUNT VALIDATION")
    print("=" * 70)

    all_ok = True

    for table_name, csv_count in csv_counts.items():

        db_count = database_counts[
            table_name
        ]

        status = (
            "✓"
            if csv_count == db_count
            else "✗"
        )

        print(
            f"{status} "
            f"{table_name:<20} "
            f"CSV: {csv_count:>10,} | "
            f"DB: {db_count:>10,}"
        )

        if csv_count != db_count:
            all_ok = False

    if not all_ok:

        raise RuntimeError(
            "Rows' number in  CSV и PostgreSQL is different"

        )

    print(
        "\n Row counts coincide"
    )



# Main


def main():

    test_connection()

    validate_processed_files()

    recreate_schema()

    csv_counts = load_all_tables()

    database_counts = (
        get_database_counts()
    )

    validate_row_counts(
        csv_counts,
        database_counts,
    )

    print("\n" + "=" * 70)
    print("POSTGRESQL LOAD COMPLETED SUCCESSFULLY")
    print("=" * 70)


if __name__ == "__main__":

    main()