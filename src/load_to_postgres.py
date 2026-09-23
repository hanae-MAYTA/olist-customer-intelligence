"""Load the cleaned CSV files into PostgreSQL, build the RFM views and export
them to CSV for Power BI.

Prerequisites: run src/clean_data.py first and fill in .env.
Usage:  python src/load_to_postgres.py
"""

import logging

import pandas as pd
from sqlalchemy import Connection, text

from config import PROCESSED_DIR, SQL_DIR, get_engine

logger = logging.getLogger(__name__)

# Parent tables first so that foreign keys are satisfied.
TABLES = ["customers", "sellers", "products", "orders", "order_items", "payments", "reviews"]
VIEWS_TO_EXPORT = [
    "rfm_customer_segments",
    "segment_category_analysis",
    "segment_satisfaction",
    "segment_geography",
]


def run_sql_file(conn: Connection, file_name: str) -> None:
    # Raw DBAPI cursor: runs multi-statement scripts and leaves "%" untouched.
    with conn.connection.cursor() as cursor:
        cursor.execute((SQL_DIR / file_name).read_text(encoding="utf-8"))
    logger.info("Executed sql/%s", file_name)


def load_table(conn: Connection, table: str) -> None:
    path = PROCESSED_DIR / f"{table}_clean.csv"
    if not path.exists():
        raise FileNotFoundError(f"{path} not found. Run `python src/clean_data.py` first.")
    # dtype=str keeps zip codes intact; PostgreSQL casts values to the column types.
    df = pd.read_csv(path, dtype=str)
    df.to_sql(table, conn, if_exists="append", index=False, chunksize=10_000, method="multi")
    logger.info("%-12s %8d rows loaded", table, len(df))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    engine = get_engine()

    # Single transaction: the database is never left half-loaded.
    with engine.begin() as conn:
        run_sql_file(conn, "01_schema.sql")
        for table in TABLES:
            load_table(conn, table)
        run_sql_file(conn, "02_rfm_views.sql")

    with engine.connect() as conn:
        for view in VIEWS_TO_EXPORT:
            df = pd.read_sql(text(f"SELECT * FROM {view}"), conn)
            df.to_csv(PROCESSED_DIR / f"{view}.csv", index=False)
            logger.info("Exported %s (%d rows) for Power BI", view, len(df))


if __name__ == "__main__":
    main()
