from pathlib import Path
import os

import mysql.connector
import pandas as pd

# Project paths
BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
CSV_FILE = DATA_DIR / "DataCoSupplyChainDataset.csv"

# Columns excluded for privacy and relevance
EXCLUDED_COLUMNS = [
    "Customer Email",
    "Customer Fname",
    "Customer Lname",
    "Customer Password",
    "Customer Street",
    "Customer Zipcode",
    "Order Zipcode",
    "Product Image",
    "Product Description",
]


def get_connection():
    """Connect to the MySQL supply_chain database."""

    password = os.getenv("MYSQL_PASSWORD")

    if not password:
        password = input("Enter MySQL password: ")

    return mysql.connector.connect(
        host="127.0.0.1",
        port=3306,
        user="root",
        password=password,
        database="supply_chain"
    )


def load_data(replace_existing=False):
    """
    Load the DataCo dataset into MySQL in batches.

    Existing records are protected by default.
    Set replace_existing=True only when intentionally
    replacing the existing orders table data.
    """

    if not CSV_FILE.exists():
        raise FileNotFoundError(
            f"Dataset not found: {CSV_FILE}"
        )

    # Read and prepare dataset
    orders = pd.read_csv(
        CSV_FILE,
        encoding="latin-1"
    )

    orders = orders.drop(
        columns=EXCLUDED_COLUMNS,
        errors="ignore"
    )

    orders.columns = [
        col.strip().replace(" ", "_").replace("-", "_")
        for col in orders.columns
    ]

    con = get_connection()
    cursor = con.cursor()

    try:
        # Check whether the orders table already exists
        cursor.execute("SHOW TABLES LIKE 'orders'")
        table_exists = cursor.fetchone() is not None

        if table_exists:
            cursor.execute("SELECT COUNT(*) FROM orders")
            existing_rows = cursor.fetchone()[0]

            if existing_rows > 0 and not replace_existing:
                raise RuntimeError(
                    "The orders table already contains data. "
                    "Loading stopped to protect existing records."
                )

            if replace_existing:
                cursor.execute("TRUNCATE TABLE orders")

        else:
            column_definitions = ", ".join(
                f"`{col}` TEXT" for col in orders.columns
            )

            cursor.execute(
                f"CREATE TABLE orders ({column_definitions})"
            )

        # Prepare batch insertion
        columns = ", ".join(
            f"`{col}`" for col in orders.columns
        )

        placeholders = ", ".join(
            ["%s"] * len(orders.columns)
        )

        insert_sql = (
            f"INSERT INTO orders ({columns}) "
            f"VALUES ({placeholders})"
        )

        batch_size = 1000

        for start in range(0, len(orders), batch_size):

            batch = orders.iloc[
                start:start + batch_size
            ]

            values = [
                tuple(
                    None if pd.isna(value) else str(value)
                    for value in row
                )
                for row in batch.itertuples(
                    index=False,
                    name=None
                )
            ]

            cursor.executemany(insert_sql, values)
            con.commit()

            print(
                f"Loaded {min(start + batch_size, len(orders))}"
                f" / {len(orders)} rows"
            )

        print("Dataset loaded successfully into MySQL!")

    except Exception:
        con.rollback()
        raise

    finally:
        cursor.close()
        con.close()


if __name__ == "__main__":
    load_data()