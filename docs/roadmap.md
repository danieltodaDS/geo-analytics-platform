# Geo Analytics Platform — Roadmap

> Este documento cobre o escopo e ciclo de desenvolvimento da v1.
> Desenvolvimentos futuros: [`docs/backlog.md`](backlog.md).

---

## Visão Geral

```
Fase 1 — v1 (foco atual)
Analytics Engineering completo — local + remoto em produção
Fontes: Olist + IBGE Localidades + Censo 2022 + BCB PIX
Mart: mart_geo_analytics pronto para análise causal
```

---

## Fase 1 — v1: Geo Analytics Platform

### Escopo Congelado

**Fonte de negócio (1):**
- Olist — dataset Kaggle, carga batch única, pedidos 2015–2018

**Fontes de covariáveis (3):**
- BCB PIX — `TransacoesPorMunicipio` (OData)
- IBGE Censo 2022 — agregados municipais via SIDRA
- IBGE Localidades — municípios, estados, regiões via servicodados.ibge.gov.br

**Mart (1):**
- `mart_geo_analytics` — unidade municipal, métricas de negócio + covariáveis prontas para o modelo causal

---

### Definição de Pronto — v1

A v1 só está concluída quando o projeto estiver rodando de ponta a ponta nas três etapas abaixo. Cada etapa é pré-requisito da seguinte.

**Local — Fase A (sem dependência de cloud):**
- Scripts de ingestão rodam via `make pipeline`
- Parquet salvo no filesystem local (`data/raw/`)
- dbt roda localmente via `dbt-duckdb` contra os Parquet locais
- Testes dbt passam
- Streamlit roda localmente contra DuckDB — **protótipo, não o produto final**
- Projeto reproduzível por qualquer pessoa que clone o repositório, sem credenciais de cloud

**Local — Fase B (warehouse real, execução local):**
- Scripts de ingestão continuam rodando via `make pipeline`
- Parquet salvo no filesystem local
- dbt migrado de `dbt-duckdb` para `dbt-bigquery` — ajustes de dialeto SQL esperados e planejados
- Testes dbt passam contra o BigQuery
- Streamlit aponta para BigQuery

**Remoto (GCP):**
- Ingestão via GitHub Actions `workflow_dispatch` — mesmo script Python, sem Docker ou Cloud Run
- Parquet no GCS → BigQuery — raw → staging → intermediate → mart
- dbt via GitHub Actions (dbt-core) ou dbt Cloud — ambos válidos
- CI/CD via GitHub Actions ativo (`ci.yml` para PRs, `ingest.yml` para ingestão manual)

Nenhum componente é opcional para considerar a v1 entregue.

---

### Ciclo de Desenvolvimento

Toda feature segue quatro etapas:

```
Explorar      → notebook, entende o dado de verdade
Entender      → documenta o que aprendeu
Especificar   → escreve a spec (só após exploração)
Produtizar
  4a. Local A → Parquet local; dbt-duckdb; Streamlit protótipo local
  4b. Local B → Parquet local; dbt migrado para BigQuery (dialeto); Streamlit → BigQuery
  4c. Remoto  → Cloud Run + GCS + BigQuery em produção
```

A produtização segue essa progressão em todas as features. Fase 4a valida a lógica sem dependência de cloud. Fase 4b valida a integração com o warehouse. Fase 4c é o deploy.

---

### Features

#### Feature 1 — Ingestão Fontes de Negócio

Cobre datasets históricos de e-commerce com granularidade municipalizável.

**Explorar — por fonte (ex: Olist)**
- Baixar dataset via Kaggle API
- Inspecionar schema de cada tabela
- Entender volume, nulos, tipos, encoding
- Identificar como resolver município a partir do dado (CEP → código IBGE)
- Verificar período coberto e lacunas temporais

**Entender**
- Documentar schema real encontrado
- Registrar anomalias
- Definir estratégia de geocodificação
- Confirmar período mínimo para viabilidade do experimento

**Especificar** → `specs/ingestion/{fonte}.md`

**Produtizar**
- Script `ingestion/src/{fonte}.py`
- Validação Pydantic
- Testes unitários

---

#### Feature 2 — Ingestão IBGE

Cobre Localidades e Censo 2022 — duas APIs distintas no mesmo domínio.

**Explorar**
- Testar endpoint Localidades — cobertura dos 5.570 municípios
- Testar SIDRA — estrutura de tabelas, filtros por variável e período
- Tabelas-chave: `9606` (internet), `9605` (renda), `9514` (população)
- Entender paginação, rate limit, formato de resposta

**Entender**
- Documentar schema real de cada endpoint
- Confirmar cobertura municipal completa no Censo 2022
- Definir quais variáveis do SIDRA usar como covariáveis

**Especificar** → `specs/ingestion/ibge.md`

**Produtizar**
- `ingestion/src/ibge_localidades.py`
- `ingestion/src/ibge_censo.py`
- Retry com Tenacity em ambos
- Validação Pydantic
- Testes unitários

---

#### Feature 3 — Ingestão BCB PIX

**Explorar**
- Testar endpoint `TransacoesPorMunicipio`
- Entender filtros por período e município
- Verificar granularidade municipal — todos os municípios ou só os maiores?
- Entender paginação OData (`$top`, `$skip`, `$filter`)

**Entender**
- Documentar schema real
- Registrar municípios sem cobertura e definir tratamento
- Confirmar periodicidade real e lag de publicação
- Documentar gap temporal com Olist (PIX existe a partir de 2020)

**Especificar** → `specs/ingestion/bcb_pix.md`

**Produtizar**
- `ingestion/src/bcb_pix.py`
- Retry com Tenacity
- Validação Pydantic
- Testes unitários

---

#### Feature 4 — dbt Staging

**Explorar**
- Inspecionar dado raw no BigQuery após ingestão de todas as fontes
- Identificar campos que precisam de limpeza por fonte
- Para fontes de negócio: validar estratégia de geocodificação (CEP → IBGE)

**Entender**
- Documentar transformações necessárias por fonte
- Definir convenção de renomeação de colunas
- Documentar premissas de geocodificação por fonte de negócio

**Especificar** → `specs/dbt/staging.md`

**Produtizar**
- `stg_{fonte}_orders.sql` por fonte de negócio — inclui geocodificação
- `stg_ibge_localidades.sql`, `stg_ibge_censo.sql`
- `stg_bcb_pix.sql`
- `schema.yml` — `not_null` + `unique` em toda PK
- `sources.yml` — freshness por source

---

#### Feature 5 — dbt Intermediate

**Explorar**
- Validar joins entre staging models
- Verificar cardinalidade
- Validar cobertura municipal após geocodificação

**Entender**
- Documentar regras de negócio dos joins
- Definir schema comum das fontes de negócio: `municipio_id / ano_mes / total_pedidos / receita_total / ticket_medio / fonte`
- Documentar premissas de gap temporal (Olist 2015–2018 vs BCB PIX 2020+)

**Especificar** → `specs/dbt/intermediate.md`

**Produtizar**
- `int_{fonte}_por_municipio.sql` — padroniza cada fonte para schema comum
- `int_municipios_enriquecidos.sql` — join de todas as covariáveis
- `int_periodo_pre_pos.sql` — define janelas do experimento
- `schema.yml` com testes de relacionamento

---

#### Feature 6 — dbt Marts

**Explorar**
- Validar modelo intermediate com queries analíticas
- Verificar se métricas fazem sentido de negócio
- Identificar o que o Streamlit vai precisar consumir

**Entender**
- Documentar definição de cada métrica
- Definir quais colunas são expostas para consumo

**Especificar** → `specs/dbt/marts.md`

**Produtizar**
- `mart_municipios.sql` — perfil completo por município
- `mart_geo_analytics.sql` — dataset final com métricas + covariáveis
- `schema.yml` — suite completa de testes + descrições de colunas + owner

---

#### Feature 8 — CI/CD GitHub Actions

**Produtizar** (sem exploração necessária)
- `ci.yml` — pytest + dbt compile + dbt test (todo PR)
- `ingest.yml` — `workflow_dispatch` com input de fonte; executa script de ingestão + upload para GCS

---

#### Feature 9 — Streamlit

**Explorar**
- Prototipar visualizações em notebook
- Entender o que conta melhor a história do dado

**Entender**
- Definir as 3 visualizações principais
- Definir filtros e interatividade

**Especificar** → `specs/streamlit/dashboard.md`

**Produtizar**
- Mapa de municípios com covariáveis (Plotly)
- Distribuição de métricas por região e fonte de negócio
- **Matching por Mahalanobis:** dado um município tratado, retorna os k=5 mais similares como candidatos a controle — usando as 6 covariáveis fixadas no `docs/backlog.md` item 1; implementação via `scipy.cdist`; k configurável via widget no Streamlit

> Escopo deliberado: apenas a seleção de pares (matching). DiD, PSM e Geo Lift permanecem no backlog item 1 como pós-v1.

---

### Ordem de Construção — v1

```
Documentação
1. README + escopo
2. ADRs
3. docs/normative/conventions.md + docs/normative/data_quality.md

--- Local A — sem dependência de cloud ---
4.  Feature 1 — Ingestão Olist           (4a: Parquet local)
5.  Feature 2 — Ingestão IBGE            (4a: Parquet local)
6.  Feature 3 — Ingestão BCB PIX         (4a: Parquet local)
7.  Feature 4 — dbt Staging              (4a: dbt-duckdb)
8.  Feature 5 — dbt Intermediate         (4a: dbt-duckdb)
9.  Feature 6 — dbt Marts               (4a: dbt-duckdb)
10. Feature 9 — Streamlit                (4a: protótipo local contra DuckDB)

--- Local B — dbt contra BigQuery ---
11. Features 4–6                         (4b: migração de dialeto dbt-duckdb → dbt-bigquery)
12. Feature 9 — Streamlit                (4b: Streamlit → BigQuery)

--- Preparação para remoto ---
13. Provisionamento GCP (one-time, via gcloud):
    - Bucket GCS para Parquet raw
    - Datasets BigQuery: dataset_raw, dbt_staging, dbt_intermediate, dbt_marts
    - Service account + Workload Identity Federation para GitHub Actions (ADR-009)
14. Feature 8 — CI/CD GitHub Actions (ci.yml + ingest.yml)

--- Remoto — GCP em produção ---
15. Features 1–6 + 8–9                   (4c: GitHub Actions + GCS + BigQuery)
16. Feature 9 — Streamlit                (4c: deploy final)

Documentação final
17. Documentar prompts Claude Code usados
```

---

## Desenvolvimentos Futuros

Pré-requisito: v1 em produção.

Backlog de itens independentes, sem ordem obrigatória — ver [`docs/backlog.md`](backlog.md):
- Inferência causal (DiD, Propensity Score, KNN, Geo Lift)
- Agentes de análise e qualidade narrativa
- Fontes adicionais de covariáveis e negócio
