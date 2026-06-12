.PHONY: pipeline ingest transform test streamlit auth setup-gcloud bq-load

auth:
	gcloud auth login
	gcloud auth application-default login

setup-gcloud: auth
	gcloud config set project data-pipeline-lab-497514
	gcloud services list --enabled --filter="name:bigquery"
	bq mk --dataset --if-not-exists --location=US data-pipeline-lab-497514:raw
	bq mk --dataset --if-not-exists --location=US data-pipeline-lab-497514:staging
	bq mk --dataset --if-not-exists --location=US data-pipeline-lab-497514:intermediate
	bq mk --dataset --if-not-exists --location=US data-pipeline-lab-497514:marts
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

streamlit:
	uv run streamlit run streamlit/app.py
