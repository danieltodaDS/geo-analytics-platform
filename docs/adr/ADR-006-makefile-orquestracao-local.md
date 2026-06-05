# ADR-006: Makefile como Orquestrador Local

**Status:** Aceito
**Supersede:** ADR-004
**Data:** Junho/2026

---

## Decisão

Substituir o Airflow local por Makefile para orquestração de desenvolvimento. A stack de produção (Cloud Scheduler + Cloud Run) permanece inalterada.

## Contexto

A ADR-004 adotou Airflow via Docker Compose para orquestração local. Após a fase de exploração das fontes, ficou confirmado que todos os datasets de negócio são históricos estáticos — sem incrementalidade real. Ver ADR-004 para o raciocínio completo da supersedência.

## Decisão

Makefile com targets explícitos por etapa do pipeline:

```makefile
pipeline:
	python ingestion/src/olist.py
	python ingestion/src/ibge_localidades.py
	python ingestion/src/ibge_censo.py
	python ingestion/src/bcb_pix.py
	dbt run && dbt test

ingest:
	python ingestion/src/olist.py
	python ingestion/src/ibge_localidades.py
	python ingestion/src/ibge_censo.py
	python ingestion/src/bcb_pix.py

transform:
	dbt run

test:
	pytest ingestion/tests/
	dbt test

streamlit:
	streamlit run app/dashboard.py
```

## Justificativa

- O Makefile entrega o que seria usado do Airflow (sequência de comandos com dependências) sem a complexidade de Docker Compose, workers, scheduler e banco de metadados
- Sem overengineering: a ferramenta resolve o problema real, não o problema imaginado
- Compatibilidade direta com produção — o mesmo script Python executado pelo `make` é o que o Cloud Run executa

## Consequências

- Sem interface visual de execução local — `make pipeline` no terminal é suficiente
- Sem retry automático entre steps no Makefile — falha em qualquer script interrompe o pipeline (comportamento desejado: não promover dado inválido)
- `airflow/` e `specs/airflow/` removidos do repositório
- A ausência do Airflow é documentada nesta ADR e na ADR-004 — não é uma lacuna
