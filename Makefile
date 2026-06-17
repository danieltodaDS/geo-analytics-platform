ifneq (,$(wildcard .env))
include .env
export
endif

.PHONY: pipeline ingest transform test streamlit auth setup-gcloud setup-external-tables cost

auth:
	gcloud auth login
	gcloud auth application-default login

setup-gcloud: auth
	gcloud config set project data-pipeline-lab-497514
	gcloud services list --enabled --filter="name:bigquery"
	bq mk --dataset --location=US data-pipeline-lab-497514:raw
	bq mk --dataset --location=US data-pipeline-lab-497514:staging
	bq mk --dataset --location=US data-pipeline-lab-497514:intermediate
	bq mk --dataset --location=US data-pipeline-lab-497514:marts
	bq ls --project_id=data-pipeline-lab-497514

setup-external-tables:
	bash infra/setup_external_tables.sh

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

cost:
	@echo "=== BigQuery — últimos 30 dias ==="
	@bq query --nouse_legacy_sql --format=pretty \
	'SELECT DATE(creation_time) AS dia, COUNT(*) AS jobs, \
	 ROUND(SUM(total_bytes_billed)/POW(1024,4)*6.25,4) AS usd_estimado, \
	 ROUND(SUM(total_bytes_billed)/POW(1024,3),2) AS gb_billed \
	 FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT \
	 WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) \
	   AND job_type = "QUERY" AND state = "DONE" \
	 GROUP BY dia ORDER BY dia DESC LIMIT 15'
	@echo ""
	@echo "=== GCS — storage atual ==="
	@gsutil du -sh gs://geo-analytics-platform-raw/
