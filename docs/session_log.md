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
- Próximo: Feature 5 — dbt intermediate

---

**2026-06-08**
- Sessão conceitual + refinamento de política: raw=view (filtro partição obrigatório), staging=table full-refresh, intermediate=table (joins+dedup semântica), marts=table; ADR-008 criado
- Política de qualidade staging reformulada: `row_hash` (md5 all cols + coalesce) universal em todos os 13 modelos — serve como fingerprint de dedup técnica (QUALIFY) e mecanismo de idempotência para cargas incrementais
- `meta.natural_pk` adicionado no `_staging.yml` de todos os modelos — comunica ao intermediate quais colunas testar com `not_null + unique` após dedup semântica
- `CLAUDE.md` atualizado com docs normativos (`roadmap.md`, `conventions.md`, `data_quality.md`) e testes obrigatórios por camada; `docs/geo_lift_scope.md` duplicado removido
- 41/41 testes dbt staging passando; Próximo: Feature 5 — dbt intermediate

---

**2026-06-08 (continuação)**
- `specs/dbt/intermediate.md` completa: 7 modelos novos especificados (int_olist_order_items_agg, int_olist_order_reviews_agg, int_dim_customers, int_dim_sellers, int_dim_products, int_fact_orders) + 2 já existentes
- Decisões: sem filtro de status no intermediate (responsabilidade do mart); geografia do fact usa CEP do pedido (stg_customers), não CEP modal da dim; int_dim_customers/sellers/products consumidas no mart, não no fact
- Spec revisada pelo Validador: 7 ressalvas resolvidas — diagrama de dependências, cobertura de geolocalização, testes de sanidade (approval_days >= 0), débitos técnicos documentados
- Próximo: implementar modelos intermediate em dbt (começar pelas pré-agregações, depois dims, depois fact)

---

**2026-06-08 (continuação 2)**
- 8 modelos intermediate implementados e passando: int_olist_geolocation, int_olist_order_payments_agg, int_olist_order_items_agg, int_olist_order_reviews_agg, int_dim_customers, int_dim_sellers, int_dim_products, int_fact_orders
- `dbt_utils 1.3.3` adicionado via `packages.yml` (necessário para `expression_is_true`)
- 31/31 testes passando; ajustes pós-validação: `total_revenue >= 0`, `not_null` em customer_unique_id, remoção de review_answer_timestamp, documentação de MODE tie em int_dim_customers
- Débitos técnicos de dialeto documentados na spec: `datediff` e `mode()` incompatíveis com BigQuery — plano de ação na fase 4b
- Próximo: Feature 6 — dbt marts

---

**2026-06-08 (continuação 3)**
- Descoberta: tabelas SIDRA 9605 e 9606 eram de população desagregada (não renda/internet) — identificadas via exploração empírica
- Fix completo de ingestão: 9605→10295 (rendimento médio/mediano, R$), 9606→9936 (% domicílios com internet, filtro c2072/77585)
- `_TABELAS_CONFIG` consolidou 3 dicts separados; novo teste de volume diferenciado por tabela; 35/35 testes passando
- 43/43 testes dbt staging passando; `docs/understanding/ibge.md` e `docs/vision/fontes_covariaveis_municipais.md` atualizados
- Próximo: especificar e implementar intermediate IBGE (int_ibge_censo_covariaveis + int_ibge_municipios)

---
