# Geo Analytics Platform

Pipeline de Analytics Engineering para mensuração de causalidade em expansão geográfica de produto digital, construído sobre dados públicos brasileiros no GCP.

---

## Problema de Negócio

> "A expansão de um produto digital para novas regiões causou aumento nas métricas de negócio, ou elas já iriam crescer de qualquer jeito?"

Responder essa pergunta exige causalidade — não correlação. Este projeto constrói a infraestrutura analítica completa para responder essa pergunta com rigor estatístico, usando dados públicos brasileiros como covariáveis e o dataset Olist como fonte de negócio.

---

## Fases do Projeto

```
Fase 1 — Analytics Engineering  ← concluída
Ingestão → Raw Layer → dbt → Streamlit

Fase 2 — Data Science            (roadmap)
Matching Estatístico + Diferença em Diferenças

Fase 3 — AI Engineering          (roadmap)
Agentes de monitoramento e análise do experimento
```

---

## Arquitetura

```
Fontes de Negócio
└── Olist (Kaggle)                      ← o que medir

Covariáveis Municipais
├── IBGE Localidades + Censo 2022       ← contexto demográfico para matching
└── BCB PIX por Município               ← adoção de pagamento digital

                    ↓

Ingestão
├── Local:      make ingest-local → scripts Python → Parquet em data/raw/
└── Produção:   GitHub Actions (workflow_dispatch) → scripts Python → GCS

                    ↓

Raw Layer — Google Cloud Storage
gs://geo-analytics-platform-raw/raw/{fonte}/year=X/month=X/day=X/data.parquet

                    ↓

Warehouse — BigQuery (External Tables sobre GCS)
├── raw          ← External Tables sobre Parquets no GCS
├── staging      ← limpeza, tipagem, geocodificação (dbt)
├── intermediate ← joins entre fontes, schema comum, regras de negócio (dbt)
└── marts        ← modelos finais prontos para consumo (dbt)

                    ↓

Visualização — Streamlit
└── Análise exploratória e matching de municípios similares
```

---

## Stack

| Camada | Ferramenta |
|---|---|
| Ingestão | Python 3.11 |
| Validação de schema | Pydantic |
| Retry de API | Tenacity |
| Logging | structlog |
| Orquestração local | Makefile |
| Orquestração produção | GitHub Actions (workflow_dispatch) |
| Storage raw | Google Cloud Storage |
| Warehouse | BigQuery |
| Transformação | dbt Core |
| Qualidade | dbt tests |
| CI (lint/test) | GitHub Actions |
| Visualização | Streamlit + Plotly |
| Harness / AI | Claude Code |

---

## Como Rodar

### Pré-requisitos

```bash
# Python 3.11 + uv
uv sync

# Autenticação GCP + criação dos datasets BigQuery + External Tables
make auth
make setup-gcloud
make setup-external-tables
```

### Local

Ingestão local (Parquet em `data/raw/`) + dbt contra BigQuery via ADC.

> **Olist:** dataset estático baixado do Kaggle ([Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)). Após baixar, extraia os CSVs em `data/olist/` (ex: `data/olist/olist_orders_dataset.csv`). Execute `make ingest-local` para gerar os Parquets. Para subir ao GCS: `make olist-upload`.

```bash
make pipeline-local   # ingestão + dbt build + testes
make ingest-local     # apenas ingestão
make transform-local  # apenas dbt build
make test             # pytest + dbt test
make streamlit        # app local contra BigQuery
```

### Produção (GitHub Actions)

```bash
make pipeline-remote    # ingest + transform sequencial via Actions
make ingest-remote      # apenas ingestão (todas as fontes dinâmicas)
make transform-remote   # apenas dbt build
```

Ou pelo painel do GitHub: **Actions → Pipeline / Ingest / Transform → Run workflow**.

### Monitoramento de custos

```bash
make cost   # BigQuery jobs (últimos 30 dias) + GCS storage
```

---

## Escopo v1

**Fonte de negócio:**
- Olist — dataset Kaggle, período 2015–2018, carga batch única

**Covariáveis municipais:**
- IBGE Localidades — tabela referencial de todos os municípios brasileiros
- IBGE Censo 2022 (SIDRA) — população, renda per capita, acesso à internet por município
- BCB PIX — volume e quantidade de transações PIX por município (a partir de 2020)

**Output:**
- `mart_geo_analytics` — unidade municipal com métricas de negócio + covariáveis, pronto para o modelo causal da Fase 2

---

## Estrutura do Repositório

```
geo-analytics-platform/
├── .github/workflows/
│   ├── ci.yml              ← pytest + dbt parse (a cada PR/push)
│   ├── ingest.yml          ← ingestão por fonte (workflow_dispatch)
│   ├── transform.yml       ← dbt build completo (workflow_dispatch)
│   └── pipeline.yml        ← ingest + transform sequencial (workflow_dispatch)
├── docs/
│   ├── adr/                ← decisões arquiteturais
│   ├── normative/          ← convenções e regras de qualidade
│   ├── roadmap.md
│   └── backlog.md
├── exploration/            ← notebooks exploratórios (gitignored)
├── ingestion/
│   ├── src/                ← scripts de ingestão por fonte
│   └── tests/
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── marts/
│   ├── macros/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   └── packages.yml
├── streamlit/
├── Makefile
└── pyproject.toml
```

---

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/adr/`](docs/adr/) | Decisões arquiteturais com contexto e alternativas descartadas |
| [`docs/normative/`](docs/normative/) | Convenções de código, qualidade de dados e contratos entre camadas |
| [`docs/roadmap.md`](docs/roadmap.md) | Escopo, sequência de construção e fases futuras |
| [`docs/backlog.md`](docs/backlog.md) | Itens pós-v1 (inferência causal, segmentação, agentes) |
