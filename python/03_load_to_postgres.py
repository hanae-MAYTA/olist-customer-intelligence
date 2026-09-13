import pandas as pd
from sqlalchemy import create_engine

engine = create_engine("postgresql://postgres:postgres@localhost:5432/customer_intelligence")

PROCESSED = "data/processed/"

tables = {
    "customers":   "customers_clean.csv",
    "orders":      "orders_clean.csv",
    "order_items": "order_items_clean.csv",
    "payments":    "payments_clean.csv",
    "products":    "products_clean.csv",
    "sellers":     "sellers_clean.csv",
    "reviews":     "reviews_clean.csv",
}

for table_name, file_name in tables.items():
    df = pd.read_csv(PROCESSED + file_name)
    df.to_sql(table_name, engine, if_exists="append", index=False)
    print(f" {table_name} : {len(df)} lignes importées")