# Session Log

<!-- Atualizado pelo Agente Executor ao final de cada sessão. Máx 5 linhas por entrada. -->

---

**2026-06-04**
- Exploração IBGE: adicionadas células de inspeção JSON bruto ao notebook; schema real capturado (Localidades tem hierarquia dupla microrregiao/regiao-imediata; SIDRA usa chaves internas NC/D1C/V)
- Criados: `docs/understanding/ibge.md`, `specs/ingestion/ibge.md` (Pydantic models, Tenacity, edge cases)
- Criados: ADRs 001–006, README, `docs/conventions.md`, `docs/sources.md`, `docs/data_quality.md`
- Decisões: `RAW_BASE_PATH` controla destino local vs GCS; SIDRA raw armazena chaves internas (rename é do staging); commits atômicos por unidade lógica

**2026-06-04 (continuação)**
- Feature 2A concluída: `ibge_localidades.py`, `ibge_censo.py`, `test_ibge.py` (14 testes, todos passando)
- Convenção uv adicionada ao CLAUDE.md e conventions.md; dependências instaladas via `uv add`
- Decisões: falha em qualquer tabela SIDRA aborta o run inteiro (write parcial é pior que sem write)
- Próximo: Feature 2B — carregar Parquet local no BigQuery via `bq load`, dbt contra BigQuery

---

**2026-06-05**
- Ciclo de desenvolvimento revisto: fase 4a agora cobre ingestão + dbt-duckdb + Streamlit protótipo (local completo antes do cloud); ADR-007 documenta dbt-duckdb e riscos de dialeto
- Features 1, 2, 3 fase 4a concluídas: `olist.py` (9 tabelas), `ibge_localidades.py`, `ibge_censo.py`, `bcb_pix.py` — 34 testes passando, Parquets em `data/raw/`
- Decisões: Olist sem fase 4c (dataset estático); microrregiao/mesorregiao Optional no IBGE (1 município sem hierarquia antiga); BCB PIX filtra nulos por Municipio_Ibge e Estado_Ibge
- dbt configurado: dbt-duckdb 1.10.1 instalado, `dbt_project.yml` e `profiles.yml` criados, `dbt debug` OK
- Próximo: Feature 4 — dbt Staging (explorar Parquets locais, escrever stg_*.sql contra DuckDB)

---

**2026-06-05 (continuação)**
- Sessão de dúvidas conceituais: explicados `dbt_project.yml` (name, profile, model-paths, materialização por camada) e demais arquivos de config dbt (`profiles.yml`, `.user.yml`)
- Nenhum código alterado
- Próximo: Feature 4 — dbt Staging (stg_*.sql contra DuckDB)

---

**2026-06-07**
- BCB PIX ingestão executada: 378.663 registros, 68 nulos descartados, Parquet em `data/raw/bcb_pix/year=2026/month=06/day=07/`
- Camada raw dbt criada: 13 views no schema `raw` (réplica fiel dos Parquets) — espelha `dataset_raw` do BigQuery
- Arquitetura ELT local consolidada: Parquets → source → raw → staging → intermediate → marts
- `generate_schema_name.sql` adicionado; `dbt_project.yml` atualizado com schema por camada
- `specs/dbt/raw.md` criada (spec retroativa à camada raw)
- Próximo: Feature 4 — staging (stg_*.sql lendo de `{{ ref() }}` da camada raw)

---
