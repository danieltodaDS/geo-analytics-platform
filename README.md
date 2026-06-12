# Geo Analytics Platform

Pipeline de Analytics Engineering para mensuração de causalidade em expansão geográfica de produto digital, construído sobre dados públicos brasileiros no GCP.

---

## Problema de Negócio

> "A expansão de um produto digital para novas regiões causou aumento nas métricas de negócio, ou elas já iriam crescer de qualquer jeito?"

Responder essa pergunta exige causalidade — não correlação. Este projeto constrói a infraestrutura analítica completa para responder essa pergunta com rigor estatístico, usando dados públicos brasileiros como covariáveis e o dataset Olist como fonte de negócio.

---

## Fases do Projeto

```
Fase 1 — Analytics Engineering  ← foco atual
Ingestão → Raw Layer → dbt → Qualidade → Streamlit

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
├── Local:      make pipeline → scripts Python
└── Produção:   Cloud Scheduler → Cloud Run Job → scripts Python

                    ↓

Raw Layer — Google Cloud Storage
gs://bucket/raw/{fonte}/year=X/month=X/day=X/data.parquet

                    ↓

Warehouse — BigQuery
├── dev_raw          ← carga direta do GCS, sem transformação
├── dev_staging      ← limpeza, tipagem, geocodificação (dbt)
├── dev_intermediate ← joins entre fontes, schema comum, regras de negócio (dbt)
└── dev_marts        ← modelos finais prontos para consumo (dbt)

                    ↓

Qualidade — Elementary
├── Freshness por source
├── Anomalias de volume
└── Dashboard de qualidade

                    ↓

Visualização — Streamlit
├── Mapa de municípios com covariáveis
├── Distribuição de métricas por região
└── Comparação de perfil entre regiões candidatas
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
| Orquestração produção | Cloud Scheduler + Cloud Run |
| Storage raw | Google Cloud Storage |
| Warehouse | BigQuery |
| Transformação | dbt Core |
| Qualidade | dbt tests + Elementary |
| CI/CD | GitHub Actions |
| IaC | Terraform |
| Visualização | Streamlit + Plotly |
| Harness / AI | Claude Code |

---

## Como Rodar

O pipeline segue uma progressão em três fases. Cada fase é pré-requisito da seguinte.

### Local A — sem dependência de cloud

Valida toda a lógica do pipeline sem criar nenhum recurso GCP.

```bash
make pipeline    # ingestão → Parquet em data/raw/ + dbt contra arquivos locais
make ingest      # apenas ingestão
make transform   # apenas dbt
make test        # pytest + dbt test
```

### Local B — dbt contra BigQuery

Mesmos scripts de ingestão. dbt passa a rodar contra o BigQuery real.

```bash
# Pré-requisito
gcloud auth application-default login

make pipeline    # Parquet local + dbt → BigQuery
```

### Remoto — GCP em produção

Após Local B validado e Terraform provisionado.

```bash
# Deploy via CI/CD (GitHub Actions) — não rodar manualmente
# Ver .github/workflows/deploy.yml
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
│   ├── ci.yml              ← pytest + dbt compile + dbt test + terraform plan
│   └── deploy.yml          ← build Docker + push + deploy Cloud Run
├── docs/
│   ├── adr/                ← decisões arquiteturais (ADR-001 a ADR-006)
│   ├── understanding/      ← entendimento das fontes (pós-exploração)
│   └── prompts/            ← prompts Claude Code por feature
├── exploration/            ← notebooks exploratórios (não vão para produção)
├── specs/                  ← specs por feature (pós-entendimento, pré-código)
│   ├── ingestion/
│   ├── dbt/
│   └── streamlit/
├── ingestion/
│   ├── src/                ← scripts de ingestão por fonte
│   └── tests/
├── dbt/
│   └── models/
│       ├── staging/
│       ├── intermediate/
│       └── marts/
├── streamlit/
├── terraform/
├── Makefile
└── CLAUDE.md
```

---

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/adr/`](docs/adr/) | Decisões arquiteturais com contexto e alternativas descartadas |
| [`docs/understanding/`](docs/understanding/) | Schema real das APIs, edge cases observados na exploração |
| [`specs/ingestion/`](specs/ingestion/) | Contratos de ingestão — Pydantic models, retry, testes obrigatórios |
| [`geo_lift_scope.md`](geo_lift_scope.md) | Escopo congelado v1, ciclo de desenvolvimento, convenções |

---

## Ciclo de Desenvolvimento

Toda feature segue quatro etapas obrigatórias antes de qualquer código de produção:

```
1. Explorar   → notebook em exploration/
2. Entender   → docs/understanding/{fonte}.md
3. Especificar → specs/{dominio}/{feature}.md
4. Produtizar  → código + testes
```

Cada etapa gera um commit atômico separado.
