.PHONY: pipeline ingest transform test streamlit setup-gcloud

setup-gcloud:
	gcloud auth login
	gcloud auth application-default login
	gcloud config set project data-pipeline-lab-497514
	gcloud services list --enabled --filter="name:bigquery"
	bq ls --project_id=data-pipeline-lab-497514
	bq mk --dataset --location=US data-pipeline-lab-497514:dataset_raw
	bq mk --dataset --location=US data-pipeline-lab-497514:dataset_staging
	bq mk --dataset --location=US data-pipeline-lab-497514:dataset_intermediate
	bq mk --dataset --location=US data-pipeline-lab-497514:dataset_marts

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

streamlit:
	uv run streamlit run streamlit/app.py
