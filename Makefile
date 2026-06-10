.PHONY: pipeline ingest transform test streamlit

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
