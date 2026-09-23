"""Shared project settings: file paths and database connection."""

import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import URL, Engine, create_engine

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = PROJECT_ROOT / "data" / "raw"
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
SQL_DIR = PROJECT_ROOT / "sql"
FIGURES_DIR = PROJECT_ROOT / "reports" / "figures"

load_dotenv(PROJECT_ROOT / ".env")


def get_engine() -> Engine:
    """Build a SQLAlchemy engine from the PG* variables defined in `.env`."""
    password = os.getenv("PGPASSWORD")
    if not password:
        raise RuntimeError(
            "PGPASSWORD is not set. Copy .env.example to .env and fill in your "
            "PostgreSQL credentials."
        )
    url = URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("PGUSER", "postgres"),
        password=password,
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT", "5432")),
        database=os.getenv("PGDATABASE", "customer_intelligence"),
    )
    return create_engine(url)
