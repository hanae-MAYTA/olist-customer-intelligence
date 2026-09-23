"""Clean the raw Olist CSV files and write them to data/processed/.

The cleaning decisions are justified in notebooks/01_data_exploration.ipynb.
Usage:  python src/clean_data.py
"""

import logging

import pandas as pd

from config import PROCESSED_DIR, RAW_DIR

logger = logging.getLogger(__name__)

RAW_FILES = {
    "customers": "olist_customers_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "payments": "olist_order_payments_dataset.csv",
    "reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}

# Zip code prefixes are identifiers: read them as text to keep leading zeros.
STRING_COLUMNS = {
    "customers": {"customer_zip_code_prefix": str},
    "sellers": {"seller_zip_code_prefix": str},
}

DATE_COLUMNS = {
    "orders": [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ],
    "order_items": ["shipping_limit_date"],
    "reviews": ["review_creation_date", "review_answer_timestamp"],
}

PRIMARY_KEYS = {
    "customers": ["customer_id"],
    "orders": ["order_id"],
    "order_items": ["order_id", "order_item_id"],
    "payments": ["order_id", "payment_sequential"],
    # review_id alone is not unique: 814 reviews are shared by several orders.
    "reviews": ["review_id", "order_id"],
    "products": ["product_id"],
    "sellers": ["seller_id"],
}

FOREIGN_KEYS = [
    ("orders", "customer_id", "customers"),
    ("order_items", "order_id", "orders"),
    ("order_items", "product_id", "products"),
    ("order_items", "seller_id", "sellers"),
    ("payments", "order_id", "orders"),
    ("reviews", "order_id", "orders"),
]

# The two categories missing from the official translation file.
EXTRA_TRANSLATIONS = {
    "pc_gamer": "pc_gamer",
    "portateis_cozinha_e_preparadores_de_alimentos": "portable_kitchen_food_processors",
}


def load_raw_tables() -> dict[str, pd.DataFrame]:
    tables = {}
    for name, file_name in RAW_FILES.items():
        path = RAW_DIR / file_name
        if not path.exists():
            raise FileNotFoundError(
                f"{path} not found. Download the Olist dataset from Kaggle "
                "and extract it into data/raw/ (see README)."
            )
        tables[name] = pd.read_csv(
            path,
            dtype=STRING_COLUMNS.get(name),
            parse_dates=DATE_COLUMNS.get(name),
        )
    return tables


def clean_products(products: pd.DataFrame, translation: pd.DataFrame) -> pd.DataFrame:
    """Fix column typos, flag missing categories and add English category names."""
    products = products.rename(
        columns={
            "product_name_lenght": "product_name_length",
            "product_description_lenght": "product_description_length",
        }
    )
    # Nullable integers, otherwise NaN turns them into floats ("225.0") in the CSV.
    numeric_columns = products.columns.drop(["product_id", "product_category_name"])
    products[numeric_columns] = products[numeric_columns].astype("Int64")

    # 610 products have no category: keep them (their sales count in revenue)
    # under an explicit label instead of dropping them.
    products["product_category_name"] = products["product_category_name"].fillna("unknown")

    mapping = dict(zip(translation["product_category_name"], translation["product_category_name_english"]))
    mapping.update(EXTRA_TRANSLATIONS)
    mapping["unknown"] = "unknown"
    products["product_category_name_english"] = products["product_category_name"].map(mapping)
    return products


def validate(tables: dict[str, pd.DataFrame]) -> None:
    """Fail fast if a primary key is duplicated or a foreign key is orphaned."""
    for name, key in PRIMARY_KEYS.items():
        n_duplicates = tables[name].duplicated(subset=key).sum()
        if n_duplicates:
            raise ValueError(f"{name}: {n_duplicates} duplicated values for key {key}")

    for child, column, parent in FOREIGN_KEYS:
        parent_key = PRIMARY_KEYS[parent][0]
        n_orphans = (~tables[child][column].isin(tables[parent][parent_key])).sum()
        if n_orphans:
            raise ValueError(f"{child}.{column}: {n_orphans} values missing from {parent}")

    untranslated = tables["products"]["product_category_name_english"].isna().sum()
    if untranslated:
        raise ValueError(f"products: {untranslated} categories without English translation")


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    tables = load_raw_tables()

    translation = tables.pop("category_translation")
    tables["products"] = clean_products(tables["products"], translation)

    validate(tables)

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        df.to_csv(PROCESSED_DIR / f"{name}_clean.csv", index=False)
        logger.info("%-12s %8d rows -> data/processed/%s_clean.csv", name, len(df), name)


if __name__ == "__main__":
    main()
