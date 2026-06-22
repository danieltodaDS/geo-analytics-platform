# ADR-006: Makefile como Orquestrador Local

**Status:** Aceito
**Supersede:** ADR-004
**Data:** Junho/2026
**Impactada por:** [ADR-011](ADR-011-olist-event-driven-ingest.md) — o target `olist-upload` passa a copiar CSVs para o bucket de entrada (`geo-analytics-platform-landing`), não mais para o bucket oficial de raw

---

## Decisão

Substituir o Airflow local por Makefile para orquestração de desenvolvimento. A stack de produção (Cloud Scheduler + Cloud Run) permanece inalterada.

## Contexto

A ADR-004 adotou Airflow via Docker Compose para orquestração local. Após a fase de exploração das fontes, ficou confirmado que todos os datasets de negócio são históricos estáticos — sem incrementalidade real. Ver ADR-004 para o raciocínio completo da supersedência.

## Decisão

Makefile com targets explícitos por etapa do pipeline:

```makefile
auth:
	gcloud auth login
	gcloud auth application-default login

setup-gcloud: auth
	gcloud config set project <gcp_project>
	gcloud services list --enabled --filter="name:bigquery"
	bq mk --dataset --if-not-exists --location=US <gcp_project>:raw
	bq mk --dataset --if-not-exists --location=US <gcp_project>:staging
	bq mk --dataset --if-not-exists --location=US <gcp_project>:intermediate
	bq mk --dataset --if-not-exists --location=US <gcp_project>:marts
	bq ls --project_id=<gcp_project>

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
```

- `make auth` — renovação de token (sessão); `make setup-gcloud` — provisionamento one-time (inclui auth)
- Datasets nomeados por camada (`raw`, `staging`, `intermediate`, `marts`) conforme `conventions.md`
- `bq mk --if-not-exists` torna `setup-gcloud` idempotente — seguro de re-executar

## Justificativa

- O Makefile entrega o que seria usado do Airflow (sequência de comandos com dependências) sem a complexidade de Docker Compose, workers, scheduler e banco de metadados
- Sem overengineering: a ferramenta resolve o problema real, não o problema imaginado
- Compatibilidade direta com produção — o mesmo script Python executado pelo `make` é o que o Cloud Run executa

## Consequências

- Sem interface visual de execução local — `make pipeline` no terminal é suficiente
- Sem retry automático entre steps no Makefile — falha em qualquer script interrompe o pipeline (comportamento desejado: não promover dado inválido)
- `airflow/` e `specs/airflow/` removidos do repositório
- A ausência do Airflow é documentada nesta ADR e na ADR-004 — não é uma lacuna
