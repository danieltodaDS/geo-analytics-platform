import os
from unittest.mock import patch

import pandas as pd
import pytest
import structlog.testing
from pydantic import ValidationError

import ingestion.src.olist as olist
from ingestion.src.olist import (
    OlistCategoryTranslationRaw,
    OlistCustomerRaw,
    OlistGeolocationRaw,
    OlistOrderItemRaw,
    OlistOrderPaymentRaw,
    OlistOrderRaw,
    OlistOrderReviewRaw,
    OlistProductRaw,
    OlistSellerRaw,
)

# ─── Fixtures ────────────────────────────────────────────────────────────────

CUSTOMER = {
    "customer_id": "abc123",
    "customer_unique_id": "xyz456",
    "customer_zip_code_prefix": 14409,
    "customer_city": "franca",
    "customer_state": "SP",
}

ORDER = {
    "order_id": "ord001",
    "customer_id": "abc123",
    "order_status": "delivered",
    "order_purchase_timestamp": "2018-01-01 10:00:00",
    "order_approved_at": "2018-01-01 11:00:00",
    "order_delivered_carrier_date": "2018-01-02 09:00:00",
    "order_delivered_customer_date": "2018-01-05 14:00:00",
    "order_estimated_delivery_date": "2018-01-10 00:00:00",
}

ORDER_ITEM = {
    "order_id": "ord001",
    "order_item_id": 1,
    "product_id": "prod001",
    "seller_id": "sell001",
    "shipping_limit_date": "2018-01-03 00:00:00",
    "price": 99.90,
    "freight_value": 12.50,
}

ORDER_PAYMENT = {
    "order_id": "ord001",
    "payment_sequential": 1,
    "payment_type": "credit_card",
    "payment_installments": 3,
    "payment_value": 112.40,
}

ORDER_REVIEW = {
    "review_id": "rev001",
    "order_id": "ord001",
    "review_score": 5,
    "review_comment_title": "Ótimo",
    "review_comment_message": "Chegou rápido",
    "review_creation_date": "2018-01-06 00:00:00",
    "review_answer_timestamp": "2018-01-07 00:00:00",
}

GEOLOCATION = {
    "geolocation_zip_code_prefix": 1037,
    "geolocation_lat": -23.545621,
    "geolocation_lng": -46.639292,
    "geolocation_city": "sao paulo",
    "geolocation_state": "SP",
}

PRODUCT = {
    "product_id": "prod001",
    "product_category_name": "eletronicos",
    "product_name_lenght": 40.0,
    "product_description_lenght": 250.0,
    "product_photos_qty": 3.0,
    "product_weight_g": 500.0,
    "product_length_cm": 20.0,
    "product_height_cm": 10.0,
    "product_width_cm": 15.0,
}

SELLER = {
    "seller_id": "sell001",
    "seller_zip_code_prefix": 13023,
    "seller_city": "campinas",
    "seller_state": "SP",
}


# ─── Parse por modelo ─────────────────────────────────────────────────────────

class TestParse:
    def test_parse_customer_completo(self):
        result = OlistCustomerRaw(**CUSTOMER)
        assert result.customer_id == "abc123"
        assert result.customer_zip_code_prefix == 14409

    def test_parse_order_campos_opcionais(self):
        record = {**ORDER, "order_approved_at": None, "order_delivered_carrier_date": None, "order_delivered_customer_date": None}
        result = OlistOrderRaw(**record)
        assert result.order_approved_at is None
        assert result.order_delivered_carrier_date is None
        assert result.order_delivered_customer_date is None

    def test_parse_order_campo_obrigatorio_ausente(self):
        record = {k: v for k, v in ORDER.items() if k != "order_id"}
        with pytest.raises(ValidationError):
            OlistOrderRaw(**record)

    def test_parse_order_item_completo(self):
        result = OlistOrderItemRaw(**ORDER_ITEM)
        assert result.price == 99.90

    def test_parse_payment_completo(self):
        result = OlistOrderPaymentRaw(**ORDER_PAYMENT)
        assert result.payment_value == 112.40

    def test_parse_review_campos_opcionais(self):
        record = {**ORDER_REVIEW, "review_comment_title": None, "review_comment_message": None}
        result = OlistOrderReviewRaw(**record)
        assert result.review_comment_title is None
        assert result.review_comment_message is None

    def test_parse_geolocation_completo(self):
        result = OlistGeolocationRaw(**GEOLOCATION)
        assert result.geolocation_zip_code_prefix == 1037
        assert result.geolocation_lat == -23.545621

    def test_parse_product_campos_opcionais(self):
        record = {k: None for k in PRODUCT}
        record["product_id"] = "prod001"
        result = OlistProductRaw(**record)
        assert result.product_category_name is None
        assert result.product_weight_g is None

    def test_parse_seller_completo(self):
        result = OlistSellerRaw(**SELLER)
        assert result.seller_zip_code_prefix == 13023

    def test_parse_category_translation_completo(self):
        result = OlistCategoryTranslationRaw(
            product_category_name="beleza_saude",
            product_category_name_english="health_beauty",
        )
        assert result.product_category_name == "beleza_saude"
        assert result.product_category_name_english == "health_beauty"


# ─── Volume guard ─────────────────────────────────────────────────────────────

class TestVolumeGuard:
    def _df_orders(self, n: int) -> pd.DataFrame:
        return pd.DataFrame([ORDER] * n)

    def test_volume_guard_warning(self, tmp_path):
        df = self._df_orders(10)
        with (
            patch.object(olist, "_TABELAS", {"orders": ("orders.csv", OlistOrderRaw)}),
            patch.object(olist, "_VOLUME_MINIMO", {"orders": 99_000}),
            patch("ingestion.src.olist.pd.read_csv", return_value=df),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path), "OLIST_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            olist.run()
        assert any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )

    def test_volume_guard_ok(self, tmp_path):
        df = self._df_orders(10)
        with (
            patch.object(olist, "_TABELAS", {"orders": ("orders.csv", OlistOrderRaw)}),
            patch.object(olist, "_VOLUME_MINIMO", {"orders": 5}),
            patch("ingestion.src.olist.pd.read_csv", return_value=df),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path), "OLIST_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            olist.run()
        assert not any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )
