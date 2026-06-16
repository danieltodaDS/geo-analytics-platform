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

**2026-06-08 (continuação 4)**
- `specs/ingestion/ibge.md` sincronizada com implementação: tabelas 9605/9606 → 10295/9936, endpoints, volume mínimo por tabela, testes renomeados
- `specs/dbt/intermediate_ibge.md` criada: 2 modelos — `int_ibge_censo_covariaveis` (pivot SIDRA → 1 linha/município, 4 covariáveis) e `int_ibge_municipios` (geografia + censo)
- Decisões: colunas dimensionais SIDRA descartadas (todas "Total"); hierarquias intermediárias IBGE descartadas de `int_ibge_municipios` (sem uso no pipeline); Fernando de Noronha sem cobertura Censo documentado
- 14/14 testes intermediate IBGE passando
- Próximo: intermediate BCB PIX ou marts

---

**2026-06-08 (continuação 5)**
- `logs/` raiz removido e conteúdo appendado ao `dbt/logs/`; `exploration/` removido do git (arquivos preservados no disco)
- Próximo: intermediate BCB PIX ou marts

---

**2026-06-09**
- ADR-002 supersedida por ADR-009: Cloud Run + Cloud Scheduler eliminados — cargas pontuais/esporádicas não justificam a infra
- Decisão: GitHub Actions `workflow_dispatch` para ingestão remota; autenticação via Workload Identity Federation (não SA key — repo público)
- Escopo do `ingest.yml` definido: script → Parquet → GCS → `bq load`; Terraform fora do escopo da v1
- roadmap.md atualizado: provisionamento GCP one-time (item 15, via gcloud) + renumeração; CLAUDE.md stack corrigida
- Próximo: intermediate BCB PIX ou marts

---

**2026-06-09 (continuação)**
- Reestruturação completa da documentação: sources.md removido; geo_lift_scope.md arquivado; docs/normative/ criado (conventions.md + data_quality.md); docs/understanding/ recebeu fontes_covariaveis_municipais.md
- CLAUDE.md refatorado: seção "Arquitetura de contexto" adicionada; gatilhos ADR determinísticos; redundâncias (Testes, Convenções, Ambiente) removidas; "Restrições críticas" substituiu seções duplicadas
- conventions.md: absorveu Pydantic (obrigação), structlog, credenciais; corrigiu paths IBGE (9605→10295, 9606→9936)
- data_quality.md: absorveu contrato entre camadas (Data Flow); gatilho ampliado para cobrir scripts de ingestão
- Próximo: intermediate BCB PIX ou marts

---

**2026-06-09 (continuação 2)**
- `int_bcb_pix_municipio` implementado: cast ano_mes YYYYMM → DATE, totais pagador/recebedor derivados; 15/15 testes passando (PK composta, FK → int_ibge_municipios, expression_is_true)
- `specs/dbt/intermediate_bcb.md` criada; débito técnico `strptime` vs `PARSE_DATE` documentado para fase 4b
- `CLAUDE.md` atualizado: formato obrigatório de session_log adicionado (Última etapa concluída + Em andamento)
- `mart_geo_lift` renomeado para `mart_geo_analytics` em toda a documentação (roadmap, normativas, README, ADR-005, understanding)

**Última etapa concluída:** Feature 5 — dbt Intermediate (fase 4a) — todos os modelos implementados e testados (Olist, IBGE, BCB PIX)
**Em andamento:** Feature 6 — dbt Marts (fase 4a) — não iniciada; spec ainda não existe

---

**2026-06-09 (continuação 3)**
- `geo-lift` → `geo-analytics` em toda a documentação do projeto; `mart_geo_lift` → `mart_geo_analytics`
- `docs/roadmap.md` enxugado: fases 2/3 removidas; seção "Desenvolvimentos Futuros" aponta para `docs/backlog.md`
- `docs/backlog.md` criado: 6 itens independentes (inferência causal, segmentação de municípios, agentes, fontes)
- Backlog revisado pelo validador: PSM com seleção de pares completa, DiD via regressão `statsmodels`, Geo Lift (R) separado como passo independente, KNN movido para item próprio (Segmentação de Municípios)
- `CLAUDE.md` atualizado: formato de "Em andamento" no session_log agora inclui etapa do ciclo (Explorar/Entender/Especificar/Produtizar)
- `exploration/intermediate_exploration.ipynb` criado: 11 tabelas, joins entre domínios, queries de cobertura

**Última etapa concluída:** Feature 5 — dbt Intermediate (fase 4a) — todos os modelos implementados e testados (Olist, IBGE, BCB PIX)
**Em andamento:** Feature 6 — dbt Marts (fase 4a) — Explorar — notebook intermediate_exploration.ipynb criado, exploração não executada

---

**2026-06-09 (continuação 4)**
- `docs/understanding/intermediate.md` criado: volumes reais 11 tabelas, schemas corrigidos vs spec, distribuições, coberturas geo/IBGE/PIX
- Anomalias documentadas: coluna `items_count` (spec dizia `total_items`), `review_score IS NOT NULL` no lugar de `has_review`, int_ibge_municipios já contém covariáveis (JOIN com int_ibge_censo_covariaveis desnecessário no mart)
- Cobertura cross-domain: 2.361/5.571 municípios IBGE com pedidos Olist (42,4%); PIX × IBGE 100%; covariáveis 99,98%

**Última etapa concluída:** Feature 6 — dbt Marts (fase 4a) — Entender — docs/understanding/intermediate.md criado
**Em andamento:** Feature 6 — dbt Marts (fase 4a) — Especificar — spec ainda não existe

---

**2026-06-09 (continuação 5)**
- `docs/understanding/mart_geo_analytics.md` revisado pelo Validador e consolidado: contradição order_status resolvida, cobertura quantificada em pedidos, join type=INNER definido, agregação temporal=2018, PIX pagador+recebedor ambos incluídos; design de 3 marts e métricas sugeridas
- Macro `normalize_city_name` criada: remove acentos + snake_case; colunas `_slug` adicionadas a int_ibge_municipios, int_olist_geolocation, int_dim_sellers, int_dim_customers
- Cobertura pedidos→município: 53% (lower only) → 99,2% com slug; 4.009 municípios distintos; 19/19 testes passando
- Unique test nome_municipio_slug: composto (slug + uf_sigla) — municípios homônimos em estados distintos

**Última etapa concluída:** Feature 6 — dbt Marts (fase 4a) — Entender — understanding finalizado, slug implementado no intermediate
**Em andamento:** Feature 6 — dbt Marts (fase 4a) — Especificar — specs/dbt/marts.md criada, aguarda validação

---

**2026-06-09 (continuação 6)**
- `specs/dbt/marts.md` criada: 3 modelos especificados (mart_olist, mart_ibge_pix, mart_geo_analytics)
- Spec revisada pelo Validador (8 pontos) e corrigida: FILTER→CASE WHEN, volume mínimo removido, MAX() para IBGE, fonte autoritativa de dimensões declarada, atemporalidade de vendedores_no_municipio declarada, INNER JOIN corrigido, tabela de colunas herdadas, testes de negócio completos

**Última etapa concluída:** Feature 6 — dbt Marts (fase 4a) — Especificar — specs/dbt/marts.md aprovada
**Em andamento:** Feature 6 — dbt Marts (fase 4a) — Produtizar — não iniciada

---

**2026-06-09 (continuação 7)**
- 3 marts implementados: `mart_olist` (id_municipio, ano), `mart_ibge_pix` (id_municipio, ano), `mart_geo_analytics` (id_municipio)
- `_marts.yml` criado: description em toda coluna exposta, suite completa de testes; 46/46 testes passando após pós-validação (4 ressalvas resolvidas)
- Mahalanobis matching (6 covariáveis fixadas empiricamente) incorporado à Feature 9 no roadmap; backlog item 1 reestruturado com progressão Mahalanobis→DiD→PSM→Geo Lift
- Inconsistência data_quality.md (referência a Fase 2/3 removidas) corrigida

**Última etapa concluída:** Feature 6 — dbt Marts (fase 4a) — Produtizar — 46/46 testes passando
**Em andamento:** Feature 7 — Elementary (fase 4a) — não iniciada

---

**2026-06-09 (continuação 8)**
- Validação pós-implementação de backlog/roadmap: 4 ressalvas resolvidas (nota de escopo v1 no item 1, desalinhamento temporal das covariáveis, matching com reposição documentado, k=5 definido no roadmap)
- Nenhum código alterado — apenas documentação
- Elementary removido do roadmap inteiro (sem dados atualizáveis, sem valor); movido para backlog item 7 (pós-v1); seção removida do data_quality.md; roadmap renumerado (17 itens)

- Makefile criado: targets pipeline, ingest, transform, test, streamlit (ADR-006); path ADR corrigido
- Ressalvas do validador em streamlit/app.py resolvidas: DB_PATH absoluto, classify simplificado, mediana por índice posicional

**Última etapa concluída:** Feature 9 — Streamlit (fase 4a) — Produtizar — Makefile criado, todas as ressalvas resolvidas
**Em andamento:** Features 4–6 — dbt (fase 4b) — migração de dialeto dbt-duckdb → dbt-bigquery — não iniciada

---

**2026-06-11**
- GCP provisionado: gcloud 572.0.0 + bq 2.1.32 instalados, ADC autenticada, projeto `data-pipeline-lab-497514` configurado
- 4 datasets BigQuery criados: `dataset_raw`, `dataset_staging`, `dataset_intermediate`, `dataset_marts` (location=US)
- `make setup-gcloud` adicionado ao Makefile com sequência completa de setup local
- `exploration/fase_4b_exploration.ipynb` criado e executado: schemas mapeados, 4 débitos de dialeto identificados, opções de conector Streamlit avaliadas

**Última etapa concluída:** Features 4–6 — dbt (fase 4b) — Entender — docs/understanding/fase_4b.md criado e aprovado pelo Validador
**Em andamento:** Features 4–6 — dbt (fase 4b) — Especificar — specs/dbt/fase_4b.md não iniciado

---

**2026-06-12**
- Makefile refatorado: `auth` separado de `setup-gcloud`; `bq mk --if-not-exists` torna target idempotente; `bq-load` adicionado ao `.PHONY`
- Convenção de nomenclatura BigQuery simplificada: prefixo `dev_`/`prod_` removido — datasets nomeados por camada (`raw`, `staging`, `intermediate`, `marts`); datasets BigQuery recriados; `conventions.md` atualizado como fonte da verdade; 11 arquivos de doc corrigidos
- `specs/dbt/fase_4b.md` criada e aprovada após 3 rodadas de validação — débitos de dialeto completos: `TRY_CAST→SAFE_CAST` (7 staging), `::cast→CAST` (7 staging + 1 intermediate), `normalize_city_name` cross-db (4 intermediate), `DATE_DIFF(DATE(...))` para colunas TIMESTAMP
- Decisão: critério de conclusão da fase 4b compara staging BigQuery vs volumes dos Parquets (não mart — derivado pode mascarar erros de carga)

**Última etapa concluída:** Features 4–6 — dbt (fase 4b) — Especificar — specs/dbt/fase_4b.md aprovada pelo Validador
**Em andamento:** Features 4–6 — dbt (fase 4b) — Produtizar — não iniciada

---

**2026-06-12 (continuação)**
- Adapter trocado: dbt-duckdb → dbt-bigquery 1.11.1; google-cloud-bigquery adicionado
- 13 Parquets carregados no BigQuery (raw dataset) via `make bq-load`; volumes OK
- dbt raw layer movido para dataset `raw_views` (evita conflito de nomes com bq load)
- Macros cross-db criadas: `compat_datediff`, `compat_mode`, `normalize_city_name` (BQ/DuckDB)
- Staging: TRY_CAST→SAFE_CAST, ::cast→CAST, COALESCE tipado (13 modelos); Intermediate: 5 débitos corrigidos; Marts: double→FLOAT64
- Streamlit migrado: duckdb→google-cloud-bigquery, cache_data(ttl=3600)
- Build completo: 186/186 testes passando; volumes staging OK (99.441 / 378.663 / 5.571)

**Última etapa concluída:** Features 4–6 — dbt (fase 4b) — Produtizar — 186/186 testes passando, volumes confirmados
**Em andamento:** Features 4–6 — dbt (fase 4b) — Produtizar — Streamlit não testado (pendente `make streamlit`)

---

**2026-06-12 (continuação 2)**
- Decisão arquitetural: dataset `landing` como zona de ingestão (bq load); `raw` = views dbt sobre landing — preserva contrato da fase 4a
- Spec fase_4b.md corrigida: landing como datalake, transição 4c via External Tables no mesmo dataset landing, numeração 1–11
- Revert da implementação incorreta (raw_views workaround): 44 arquivos restaurados para estado v0.1-fase-4a
- profiles.yml restaurado para DuckDB; BQ BigQuery datasets a limpar antes da reimplementação

**Última etapa concluída:** Features 4–6 — dbt (fase 4b) — Especificar — spec corrigida e aprovada pelo Validador
**Em andamento:** Features 4–6 — dbt (fase 4b) — Produtizar — pré-condições pendentes antes de iniciar

**2026-06-12 (continuação 3)**
- Datasets BQ dropados: `raw`, `raw_views`, `staging`, `intermediate`, `marts`
- 5 datasets limpos recriados: `landing`, `raw`, `staging`, `intermediate`, `marts` (location=US)
- Makefile: `landing` adicionado ao `setup-gcloud`; `--if-not-exists` removido (flag não suportado na versão bq instalada)

- Makefile: `bq-load` rule adicionada (13 tabelas → `landing`); 13/13 cargas OK; volumes confirmados
- Volumes landing: bcb_pix=378.663, ibge_localidades=5.571, olist_orders=99.441 (batem com fase 4a)

**Última etapa concluída:** Features 4–6 — dbt (fase 4b) — Produtizar — `make bq-load` executado, 13 tabelas em `landing` com volumes corretos (Passo 4 da spec concluído)
**Em andamento:** Features 4–6 — dbt (fase 4b) — Produtizar — Passos 3, 5, 6, 7, 8, 9, 10, 11 da spec ainda pendentes

---

**2026-06-15**
- Passos 3–11 da spec fase_4b executados: adapter trocado (dbt-duckdb→dbt-bigquery 1.11.1), profiles.yml migrado, _sources.yml + 13 raw models atualizados (parquet_files→landing)
- 3 macros cross-db criadas/atualizadas: `compat_datediff`, `compat_mode`, `normalize_city_name`
- Staging: TRY_CAST→SAFE_CAST, ::cast→CAST (11 modelos); fix extra zip_code_prefix INT64 (3 modelos não mapeados na spec); Marts: double→FLOAT64 (3 modelos)
- Intermediate: datediff→macro, mode→macro, FILTER WHERE→IF, strptime→PARSE_DATE; 186/186 testes passando
- Pós-validação: `_staging.yml` meta→config (13 modelos, deprecação dbt resolvida); Makefile `include .env`; Streamlit migrado (duckdb→BigQuery, `make streamlit` OK)

**Última etapa concluída:** Features 4–6 + Streamlit — fase 4b — Produtizar — 186/186 testes, `make streamlit` OK, fase 4b completa
**Em andamento:** Features 4–6 + Streamlit — fase 4c — não iniciada (GitHub Actions + GCS + BigQuery remoto)

---

**2026-06-15 (continuação)**
- `docs/understanding/fase_4c.md` criado: 6 decisões resolvidas (bucket, RAW_BASE_PATH, WIF, ci.yml, Streamlit deploy, External Tables)
- Arquitetura 4c definida: External Tables no dataset `raw` (não `landing`); `landing` eliminado; 13 raw views dbt eliminados; staging migra `ref()` → `source('raw', ...)`
- `dbt parse` confirmado empiricamente como substituto de `dbt compile` no CI (sem credenciais BQ); `dbt compile` falha sem auth
- IAM corrigido: `objectAdmin` → `objectUser` na SA de ingestão; SA Streamlit separada (somente leitura, `marts` + `jobUser`)
- `specs/dbt/fase_4b.md` seção "Transição para fase 4c" corrigida; ADR-009 atualizado com decisão ci.yml; roadmap corrigido

**Última etapa concluída:** Feature 8 — CI/CD + Infra — fase 4c — Especificar — `specs/dbt/fase_4c.md` criada e aprovada (6 ressalvas do Validador incorporadas)
**Em andamento:** Feature 8 — CI/CD + Infra — fase 4c — Produtizar — não iniciada

---

**2026-06-16**
- Branch `feat/fase-4c-remoto` criada; tag `v0.2-fase-4b` aplicada
- 13 `models/raw/*.sql` removidos; `_sources.yml` migrado (`landing` → `raw`); `dbt_project.yml` config raw órfã removida
- 13 staging models migrados: `ref()` → `source('raw', ...)`; `profiles.yml` removido do `.gitignore` (sem credenciais, necessário para CI)
- `gcsfs` adicionado; 3 scripts de ingestão atualizados: `Path(base)/...` → f-string + guard `gs://`
- `.github/workflows/ci.yml` e `ingest.yml` criados; `infra/setup_external_tables.sh` e `infra/Makefile.gcp` (gitignored) criados
- `streamlit/app.py` migrado: ADC → `st.secrets["gcp_service_account"]`; `Makefile` atualizado (bq-load removido, setup-external-tables adicionado)
- Validação local: `dbt parse` limpo, 35/35 testes passando; infra GCP (passos 2–5, 10a, 11) pendente execução manual

**Última etapa concluída:** Feature 8 — CI/CD + Infra — fase 4c — Produtizar — código completo na branch `feat/fase-4c-remoto`
**Em andamento:** Feature 8 — CI/CD + Infra — fase 4c — Produtizar — provisionamento GCP e validação remota pendentes

---
