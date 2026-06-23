import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import pandas as pd
import structlog
from pydantic import BaseModel

log = structlog.get_logger()

_OLIST_BASE_PATH = "data/olist"
_SAMPLE_SIZE = 1_000

_VOLUME_MINIMO = {
    "customers": 99_000,
    "orders": 99_000,
    "order_items": 112_000,
    "order_payments": 103_000,
    "order_reviews": 99_000,
    "geolocation": 1_000_000,
    "products": 32_000,
    "sellers": 3_000,
    "category_translation": 70,
}


class OlistCustomerRaw(BaseModel):
    customer_id: str
    customer_unique_id: str
    customer_zip_code_prefix: int
    customer_city: str
    customer_state: str


class OlistOrderRaw(BaseModel):
    order_id: str
    customer_id: str
    order_status: str
    order_purchase_timestamp: str
    order_approved_at: Optional[str] = None
    order_delivered_carrier_date: Optional[str] = None
    order_delivered_customer_date: Optional[str] = None
    order_estimated_delivery_date: str


class OlistOrderItemRaw(BaseModel):
    order_id: str
    order_item_id: int
    product_id: str
    seller_id: str
    shipping_limit_date: str
    price: float
    freight_value: float


class OlistOrderPaymentRaw(BaseModel):
    order_id: str
    payment_sequential: int
    payment_type: str
    payment_installments: int
    payment_value: float


class OlistOrderReviewRaw(BaseModel):
    review_id: str
    order_id: str
    review_score: int
    review_comment_title: Optional[str] = None
    review_comment_message: Optional[str] = None
    review_creation_date: str
    review_answer_timestamp: str


class OlistGeolocationRaw(BaseModel):
    geolocation_zip_code_prefix: int
    geolocation_lat: float
    geolocation_lng: float
    geolocation_city: str
    geolocation_state: str


class OlistProductRaw(BaseModel):
    product_id: str
    product_category_name: Optional[str] = None
    product_name_lenght: Optional[float] = None
    product_description_lenght: Optional[float] = None
    product_photos_qty: Optional[float] = None
    product_weight_g: Optional[float] = None
    product_length_cm: Optional[float] = None
    product_height_cm: Optional[float] = None
    product_width_cm: Optional[float] = None


class OlistSellerRaw(BaseModel):
    seller_id: str
    seller_zip_code_prefix: int
    seller_city: str
    seller_state: str


class OlistCategoryTranslationRaw(BaseModel):
    product_category_name: str
    product_category_name_english: str


_TABELAS = {
    "customers":      ("olist_customers_dataset.csv",       OlistCustomerRaw),
    "orders":         ("olist_orders_dataset.csv",          OlistOrderRaw),
    "order_items":    ("olist_order_items_dataset.csv",     OlistOrderItemRaw),
    "order_payments": ("olist_order_payments_dataset.csv",  OlistOrderPaymentRaw),
    "order_reviews":  ("olist_order_reviews_dataset.csv",   OlistOrderReviewRaw),
    "geolocation":    ("olist_geolocation_dataset.csv",     OlistGeolocationRaw),
    "products":       ("olist_products_dataset.csv",        OlistProductRaw),
    "sellers":             ("olist_sellers_dataset.csv",                  OlistSellerRaw),
    "category_translation": ("product_category_name_translation.csv",     OlistCategoryTranslationRaw),
}


def _validate_sample(df: pd.DataFrame, model: type[BaseModel]) -> None:
    sample = df.head(_SAMPLE_SIZE).to_dict(orient="records")
    for record in sample:
        model(**{k: (None if pd.isna(v) else v) for k, v in record.items()})


def _process_table(
    tabela: str,
    csv_file: str,
    model: type[BaseModel],
    olist_base: str,
    raw_base: str,
    today: datetime,
) -> None:
    log.info("olist.inicio_tabela", tabela=tabela)

    # guard leitura — Path() colapsa gs:// para gs:/
    if olist_base.startswith("gs://"):
        csv_path = f"{olist_base}/{csv_file}"
    else:
        csv_path = str(Path(olist_base) / csv_file)

    df = pd.read_csv(csv_path)

    if len(df) < _VOLUME_MINIMO[tabela]:
        log.warning(
            "olist.volume_baixo",
            tabela=tabela,
            total=len(df),
            minimo_esperado=_VOLUME_MINIMO[tabela],
        )

    _validate_sample(df, model)

    # guard escrita — mesma razão
    if raw_base.startswith("gs://"):
        dest = f"{raw_base}/olist_{tabela}/ingestion_date={today.date()}/data.parquet"
    else:
        dest = (
            Path(raw_base)
            / f"olist_{tabela}"
            / f"ingestion_date={today.date()}"
            / "data.parquet"
        )
        dest.parent.mkdir(parents=True, exist_ok=True)

    df.to_parquet(dest, index=False, compression="snappy")
    log.info("olist.parquet_gravado", tabela=tabela, destino_path=str(dest))


def run() -> None:
    log.info("olist.inicio")
    olist_base = os.environ.get("OLIST_BASE_PATH", _OLIST_BASE_PATH)
    raw_base = os.environ.get("RAW_BASE_PATH", "data/raw")
    today = datetime.now(tz=timezone.utc)

    try:
        for tabela, (csv_file, model) in _TABELAS.items():
            _process_table(tabela, csv_file, model, olist_base, raw_base, today)
    except Exception:
        log.error("olist.erro_fatal", exc_info=True)
        raise


if __name__ == "__main__":
    run()
