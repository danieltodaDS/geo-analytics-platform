ifneq (,$(wildcard .env))
include .env
export
endif

.PHONY: pipeline ingest transform test streamlit auth setup-gcloud bq-load

auth:
	gcloud auth login
	gcloud auth application-default login

setup-gcloud: auth
	gcloud config set project data-pipeline-lab-497514
	gcloud services list --enabled --filter="name:bigquery"
	bq mk --dataset --location=US data-pipeline-lab-497514:landing
	bq mk --dataset --location=US data-pipeline-lab-497514:raw
	bq mk --dataset --location=US data-pipeline-lab-497514:staging
	bq mk --dataset --location=US data-pipeline-lab-497514:intermediate
	bq mk --dataset --location=US data-pipeline-lab-497514:marts
	bq ls --project_id=data-pipeline-lab-497514

pipeline: ingest transform test

ingest:
	uv run python ingestion/src/olist.py
	uv run python ingestion/src/ibge_localidades.py
	uv run python ingestion/src/ibge_censo.py
	uv run python ingestion/src/bcb_pix.py

transform:
	cd dbt && uv run dbt run --profiles-dir .

test:
	uv run pytest ingestion/tests/
	cd dbt && uv run dbt test --profiles-dir .

bq-load:
	bq load --replace --autodetect --source_format=PARQUET landing.olist_customers \
		$(shell find data/raw/olist_customers -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_orders \
		$(shell find data/raw/olist_orders -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_order_items \
		$(shell find data/raw/olist_order_items -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_order_payments \
		$(shell find data/raw/olist_order_payments -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_order_reviews \
		$(shell find data/raw/olist_order_reviews -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_geolocation \
		$(shell find data/raw/olist_geolocation -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_products \
		$(shell find data/raw/olist_products -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_sellers \
		$(shell find data/raw/olist_sellers -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_localidades \
		$(shell find data/raw/ibge_localidades -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_censo_9936 \
		$(shell find data/raw/ibge_censo_9936 -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_censo_10295 \
		$(shell find data/raw/ibge_censo_10295 -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_censo_9514 \
		$(shell find data/raw/ibge_censo_9514 -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.bcb_pix \
		$(shell find data/raw/bcb_pix -name "*.parquet")

streamlit:
	uv run streamlit run streamlit/app.py
