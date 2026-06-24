# Geo Analytics Platform

Web App para identificação de municípios comparáveis como base para análises de impacto e incrementalidade, construído sobre um pipeline ELT com dados públicos brasileiros no GCP

**[→ Ver aplicação ao vivo](https://geo-analytics-platform-em9nziezhlvewacdnpztzm.streamlit.app/)**

---

## Problema de Negócio

Quando uma nova funcionalidade ou iniciativa de produto é lançada, como saber se a melhora observada foi realmente causada pela mudança?

Antes de medir impacto, é necessário encontrar grupos comparáveis que possam servir como referência para análise.

### Solução

Este projeto demonstra a construção de uma plataforma analítica para identificação de municípios similares utilizando indicadores socioeconômicos e de atividade econômica.

A solução integra ingestão, modelagem dimensional e disponibilização de dados por meio de BigQuery, dbt, GCS, GitHub Actions e Streamlit.

Os dados de negócio são provenientes do dataset público Olist (Kaggle), enriquecidos com dados do IBGE e do Banco Central.

**Observação**: o projeto tem foco na construção da infraestrutura analítica e na seleção de grupos comparáveis, não na estimação causal do impacto.

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
├── Produção (IBGE + BCB PIX):  GitHub Actions (workflow_dispatch) → scripts Python → GCS
└── Produção (Olist):           upload CSV → landing bucket → Eventarc → Cloud Function → GCS

                    ↓

Raw Layer — Google Cloud Storage
gs://geo-analytics-platform-raw/raw/{fonte}/ingestion_date=YYYY-MM-DD/data.parquet

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

### Dependências

```bash
# Python 3.11 + uv
uv sync
```

### Provisionamento inicial (one-time)

Copiar o template de configuração e ajustar as variáveis (`PROJECT`, `BUCKET`, `PROJECT_NUMBER`, `REPO`, `LANDING_BUCKET`):

```bash
cp infra/Makefile.setup.example infra/Makefile.setup
```

Em seguida, executar em ordem:

```bash
make -f infra/Makefile.setup auth                            # login GCP + ADC (owner)
make -f infra/Makefile.setup base-1 base-2 base-3   # datasets BQ + buckets raw e landing
make -f infra/Makefile.setup ci-1 ci-2 ci-3        # WIF + SA ingestão + IAM
make -f infra/Makefile.setup cf-1 cf-2 cf-3        # SA + IAM + APIs da Cloud Function
make -f infra/Makefile.setup cf-4                   # deploy Cloud Function
```

**Olist** — dataset estático do Kaggle ([Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)). Extraia os CSVs em `data/olist/` e envie ao GCS:

```bash
make -f infra/Makefile.setup olist-upload   # deposita CSVs → aciona cf-4 via Eventarc
```

Após todas as fontes dinâmicas no GCS (via `make ingest-remote` ou Actions):

```bash
make -f infra/Makefile.setup data-1   # External Tables no dataset raw do BigQuery
```

### Uso recorrente

**Local** — ingestão para `data/raw/` + dbt contra BigQuery via ADC:

```bash
make pipeline-local   # ingestão + dbt build + testes
make ingest-local     # apenas ingestão
make transform-local  # apenas dbt build
make test             # pytest + dbt test
make streamlit        # app local contra BigQuery
```

**Produção** — via GitHub Actions:

```bash
make pipeline-remote    # ingest + transform sequencial via Actions
make ingest-remote      # apenas ingestão (fontes dinâmicas: IBGE + BCB PIX)
make transform-remote   # apenas dbt build
```

Ou pelo painel do GitHub: **Actions → Pipeline / Ingest / Transform → Run workflow**.

### Monitoramento de custos

```bash
make cost   # BigQuery jobs (últimos 30 dias) + GCS storage
```

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
│   └── normative/          ← convenções e regras de qualidade
├── ingestion/
│   ├── src/
│   │   ├── olist.py, ibge_*.py, bcb_pix.py   ← scripts de ingestão por fonte
│   │   ├── main.py                             ← entry point da Cloud Function (Olist)
│   │   └── requirements.txt                    ← dependências da Cloud Function
│   └── tests/
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── marts/
│   ├── macros/
│   ├── tests/              ← singular tests de volume mínimo
│   ├── dbt_project.yml
│   ├── profiles.yml
│   └── packages.yml
├── infra/
│   ├── Makefile.setup.example      ← template de provisionamento GCP (versionado)
│   └── setup_external_tables.sh    ← DDL das External Tables (one-time)
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

