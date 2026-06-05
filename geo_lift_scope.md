# Geo Analytics Platform — Guia do Projeto

> Guia de desenvolvimento do projeto de portfólio. Documento vivo — atualizado conforme o projeto evolui.

---

## Problema de Negócio

> "A expansão de um produto digital para novas regiões causou aumento nas métricas de negócio, ou elas já iriam crescer de qualquer jeito?"

Responder essa pergunta exige causalidade — não correlação. O projeto constrói a infraestrutura analítica completa para responder essa pergunta com rigor, usando dados públicos brasileiros.

---

## Visão Geral das Fases

```
Fase 1 — Analytics Engineering (foco atual)
Ingestão → Raw Layer → dbt → Qualidade → Streamlit

Fase 2 — Data Science (roadmap)
Matching Estatístico + Diferença em Diferenças

Fase 3 — AI Engineering (roadmap)
Agentes de monitoramento e análise do experimento
```

Fases 2 e 3 estão documentadas em `docs/roadmap.md` com todo o raciocínio preservado.

---

## Escopo v1 — Congelado

> O escopo abaixo é final. Não haverá adição de fontes ou funcionalidades após este corte.

**Fonte de negócio (1):**
- Olist — dataset Kaggle, carga batch única

**Covariáveis (3):**
- IBGE Localidades — tabela referencial de municípios
- IBGE Censo 2022 — demografia, renda, internet por município
- BCB PIX — adoção de pagamento digital por município

**Mart (1):**
- `mart_geo_lift` — unidade municipal, métricas de negócio + covariáveis prontas para o modelo causal

---

## Definição de Pronto — v1

A v1 só está concluída quando o projeto estiver rodando de ponta a ponta nas três etapas abaixo. Cada etapa é pré-requisito da seguinte.

**Local — Fase A (sem dependência de cloud):**
- Scripts de ingestão rodam via `make pipeline`
- Parquet salvo no filesystem local (`data/raw/`)
- dbt roda localmente contra os arquivos Parquet locais
- Testes dbt passam

**Local — Fase B (warehouse real, execução local):**
- Scripts de ingestão continuam rodando via `make pipeline`
- Parquet salvo no filesystem local
- dbt roda localmente contra o BigQuery
- Testes dbt passam contra o BigQuery

**Remoto (GCP):**
- Ingestão via Cloud Run Jobs
- Orquestração via Cloud Scheduler
- Parquet no GCS → BigQuery — raw → staging → intermediate → mart
- IaC via Terraform provisionado
- CI/CD via GitHub Actions ativo

Nenhum componente é opcional para considerar a v1 entregue.

---

## Stack

| Camada | Ferramenta |
|---|---|
| Ingestão | Python + Cloud Run + Cloud Scheduler |
| Orquestração local | Makefile |
| Storage raw | Google Cloud Storage |
| Warehouse | BigQuery |
| Transformação | dbt Core |
| Qualidade | dbt tests + Elementary |
| CI/CD | GitHub Actions |
| IaC | Terraform |
| Visualização | Streamlit + Plotly |
| Harness / AI | Claude Code + CLAUDE.md + Specs |

---

## Fontes de Dados

O projeto separa explicitamente duas categorias de fontes:

**Fontes de negócio** — o que queremos medir. Datasets históricos de e-commerce com granularidade municipalizável. A plataforma é agnóstica à fonte — qualquer dataset que chegue no formato padronizado pode alimentar o experimento.

**Covariáveis municipais** — o contexto para o matching estatístico. Dados públicos com granularidade municipal que descrevem o perfil socioeconômico e digital de cada município.

### Fontes de Negócio — v1

| Fonte | Tipo | O que fornece |
|---|---|---|
| **Olist (Kaggle)** | Batch / CSV | Pedidos, receita, ticket médio — período 2015–2018 |

### Covariáveis Municipais — v1

| Fonte | Tipo | O que fornece |
|---|---|---|
| **IBGE — Localidades** | API REST | Tabela referencial — código IBGE, nome, UF, região de todos os municípios |
| **IBGE — Censo 2022 (SIDRA)** | API REST | Fundação demográfica — população, renda, internet, IDH por município |
| **BCB — PIX por Município** | API OData | Sinal direto de adoção de pagamento digital por município |

### Fora da v1

Todas as demais fontes (BCB IFData, Anatel SCM, IBGE Malhas, CAGED, RAIS) estão documentadas em `docs/roadmap.md` com status e versão de entrada.

---

## Arquitetura

```
Fontes de Negócio — v1
└── Kaggle (Olist)                     ← o que medir
│
Covariáveis Municipais — v1
├── IBGE — Localidades + Censo 2022    ← contexto para matching
└── BCB — PIX por Município
│
Demais fontes → v2 e futuro (ver roadmap.md)
       ↓
Ingestão
├── Local:     Makefile → scripts Python
└── Produção:  Cloud Scheduler → Cloud Run → scripts Python
       ↓
Raw Layer — Google Cloud Storage
gs://bucket/raw/{fonte}/year=X/month=X/day=X/data.parquet
       ↓
Warehouse — BigQuery
├── dataset_raw           ← carga direta do GCS
├── dataset_staging       ← limpeza, tipagem, geocodificação por fonte (dbt)
├── dataset_intermediate  ← padronização schema comum + joins com covariáveis (dbt)
└── dataset_marts         ← modelos finais agnósticos à fonte de negócio (dbt)
       ↓
Qualidade — Elementary
├── Freshness por source
├── Anomalias de volume
└── Dashboard de qualidade
       ↓
Visualização — Streamlit
├── Mapa de municípios com covariáveis
├── Distribuição de métricas por região
└── Comparação de perfil entre regiões
```

---

## Data Flow — Contrato entre Camadas

Cada camada tem um contrato claro sobre o que recebe, em que formato e qual o critério para promover o dado à próxima.

### Raw Layer — Google Cloud Storage

```
O que chega:    Dado bruto, exatamente como veio da fonte
Formato:        Parquet (JSONL como fallback para schemas variáveis)
Particionamento: raw/{fonte}/year=X/month=X/day=X/data.parquet
Imutabilidade:  Nunca sobrescrito — só append
Transformação:  Nenhuma — nem renomeação de coluna
Critério:       Qualquer dado que chegou da fonte com schema válido
Responsável:    Script de ingestão + validação Pydantic
```

### dataset_raw — BigQuery

```
O que chega:    Carga direta do GCS, sem transformação
Formato:        Tabelas com schema idêntico ao Parquet
Granularidade:  Idêntica ao raw
Transformação:  Nenhuma — só materialização no warehouse
Critério:       Carga bem-sucedida do GCS
Responsável:    Job de carga (bq load ou Airflow operator)
```

### dataset_staging — BigQuery (dbt)

```
O que chega:    Dado do dataset_raw
O que muda:     Limpeza de tipos, renomeação para snake_case,
                remoção de duplicatas técnicas, cast de datas
O que NÃO muda: Granularidade — 1 linha raw = 1 linha staging
Regras:         Sem regras de negócio — só limpeza técnica
Testes:         not_null + unique em toda PK
Critério:       Passou nos testes de schema e PK
Responsável:    dbt staging models
```

### dataset_intermediate — BigQuery (dbt)

```
O que chega:    Modelos de staging (uma ou mais fontes)
O que muda:     Joins entre fontes, agregações, regras de negócio,
                granularidade pode mudar (ex: linha por município/mês)
Regras:         Aqui entram as definições de negócio
                (ex: "município ativo = pelo menos 1 pedido no período")
Testes:         Relacionamentos entre fontes, expression_is_true
Critério:       Passou nos testes de relacionamento e negócio
Responsável:    dbt intermediate models
```

### dataset_marts — BigQuery (dbt)

```
O que chega:    Modelos intermediate
O que muda:     Seleção e exposição das colunas finais,
                métricas derivadas, flags do experimento
Regras:         Modelos prontos para consumo — sem joins adicionais necessários
Documentação:   Obrigatória — description + owner + tags em toda coluna
Testes:         Suite completa — PK, FK, accepted_values, volume mínimo
Critério:       Passou em todos os testes + documentação completa
Responsável:    dbt mart models
Consumidores:   Streamlit, Fase 2 (DS), Fase 3 (Agentes)
```

### Critério de Promoção entre Camadas

```
Fonte → Raw:         schema válido (Pydantic)
Raw → Staging:       carga bem-sucedida
Staging → Interm.:   testes de PK passando
Interm. → Marts:     testes de negócio + relacionamento passando
Marts → Consumo:     suite completa + documentação presente
```

> **Princípio:** dado com problema para no estágio onde o problema foi detectado.
> Nunca promove dado inválido para a camada seguinte.

---

## Estrutura do Repositório

```
geo-lift-project/
├── .github/
│   └── workflows/
│       ├── ci.yml          ← pytest + dbt compile + dbt test + terraform plan
│       └── deploy.yml      ← build Docker + push Artifact Registry + deploy Cloud Run
├── docs/
│   ├── adr/
│   │   ├── ADR-001-warehouse.md
│   │   ├── ADR-002-orquestracao.md
│   │   ├── ADR-003-formato-raw.md
│   │   └── ADR-004-airflow-local.md
│   ├── conventions.md      ← nomenclatura de modelos, datasets, GCS, commits
│   ├── sources.md          ← SLA por fonte, tolerância, owner
│   ├── data_quality.md     ← política de testes, freshness, alertas
│   ├── roadmap.md          ← Fases 2 e 3 completas (DS + AI Eng)
│   └── prompts/            ← prompts Claude Code por feature
│       ├── ingestion/
│       ├── dbt/
│       └── streamlit/
├── exploration/            ← notebooks exploratórios (não vão para produção)
│   ├── ibge_exploration.ipynb
│   ├── bcb_exploration.ipynb
│   └── olist_exploration.ipynb
├── specs/                  ← escritas após exploração, antes do código de produção
│   ├── ingestion/
│   │   ├── olist.md
│   │   ├── ibge.md
│   │   └── bcb.md
│   ├── dbt/
│   │   ├── staging.md
│   │   ├── intermediate.md
│   │   └── marts.md
│   └── streamlit/
│       └── dashboard.md
├── airflow/
│   ├── dags/
│   │   ├── ingestion_dag.py
│   │   └── dbt_dag.py
│   └── docker-compose.yml
├── ingestion/
│   ├── src/
│   │   ├── olist.py
│   │   ├── ibge.py
│   │   ├── bcb.py
│   │   └── schema.py       ← validação Pydantic
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── marts/
│   ├── tests/
│   └── dbt_project.yml
├── streamlit/
│   ├── app.py
│   └── requirements.txt
├── terraform/
│   ├── main.tf
│   └── variables.tf
├── Makefile
├── CLAUDE.md
└── README.md
```

---

## Roadmap AE — Fase 1

O desenvolvimento de cada feature segue quatro etapas obrigatórias.

### O Ciclo por Feature

```
1. EXPLORAR      → notebook, entende o dado de verdade
2. ENTENDER      → documenta o que aprendeu
3. ESPECIFICAR   → escreve a spec (só após exploração)
4. PRODUTIZAR
   4a. Local A   → script salva Parquet local, dbt roda contra arquivos locais
   4b. Local B   → script salva Parquet local, dbt roda contra BigQuery
   4c. Remoto    → Cloud Run + GCS + BigQuery em produção
```

A produtização segue essa progressão em todas as features. Fase 4a valida a lógica sem dependência de cloud. Fase 4b valida a integração com o warehouse. Fase 4c é o deploy.

---

### Feature 1 — Ingestão Fontes de Negócio

Cobre os datasets históricos de e-commerce ou produto digital. Cada fonte é tratada como uma instância da mesma categoria — o pipeline de ingestão é independente por fonte, mas o contrato de saída é o mesmo.

**Explorar — por fonte (ex: Olist)**
- Baixar o dataset via Kaggle API
- Inspecionar schema de cada tabela
- Entender volume, nulos, tipos, encoding
- Identificar como resolver município a partir do dado disponível (ex: CEP → código IBGE)
- Verificar período coberto e lacunas temporais

**Entender**
- Documentar schema real encontrado
- Registrar anomalias (nulos inesperados, tipos inconsistentes)
- Definir estratégia de geocodificação (CEP → município)
- Confirmar período mínimo de dados para viabilidade do experimento

**Especificar** → `specs/ingestion/{fonte}.md` — uma spec por fonte de negócio

**Produtizar**
- Script `ingestion/src/{fonte}.py` por fonte
- Validação Pydantic
- Testes unitários

---

### Feature 2 — Ingestão IBGE

Cobre duas APIs distintas tratadas como uma feature por compartilharem o mesmo domínio e chave de join (`cod_municipio`).

**Explorar**
- Testar endpoint de Localidades — verifica cobertura dos 5570 municípios
- Testar SIDRA — entender estrutura de tabelas, filtros por variável e período
- Verificar tabelas-chave: `9606` (internet), `9605` (renda), `9514` (população)
- Entender paginação, rate limit e formato de resposta de ambas as APIs

**Entender**
- Documentar schema real de cada endpoint
- Confirmar cobertura municipal completa no Censo 2022
- Definir quais variáveis do SIDRA usar como covariáveis
- Registrar edge cases (municípios sem dado, campos nulos)

**Especificar** → `specs/ingestion/ibge.md`

**Produtizar**
- Script `ingestion/src/ibge_localidades.py`
- Script `ingestion/src/ibge_censo.py`
- Retry com Tenacity em ambos
- Validação Pydantic
- Testes unitários

---

### Feature 3 — Ingestão BCB PIX

**Explorar**
- Testar endpoint `TransacoesPorMunicipio`
- Entender filtros por período e município
- Verificar granularidade municipal — todos os municípios ou só os maiores?
- Entender paginação OData (`$top`, `$skip`, `$filter`)

**Entender**
- Documentar schema real
- Registrar municípios sem cobertura e definir tratamento (null vs excluir)
- Confirmar periodicidade real e lag de publicação
- Documentar gap temporal com Olist (PIX existe a partir de 2020)

**Especificar** → `specs/ingestion/bcb_pix.md`

**Produtizar**
- Script `ingestion/src/bcb_pix.py`
- Retry com Tenacity
- Validação Pydantic
- Testes unitários

---

### Feature 4 — dbt Staging

**Explorar**
- Inspecionar dado raw no BigQuery após ingestão de todas as fontes
- Identificar campos que precisam de limpeza por fonte
- Verificar tipos, encoding, campos nulos inesperados
- Para fontes de negócio: validar estratégia de geocodificação (ex: join CEP → IBGE)

**Entender**
- Documentar transformações necessárias por fonte
- Definir convenção de renomeação de colunas
- Confirmar chave de join entre fontes (`cod_municipio` IBGE)
- Documentar premissas de geocodificação por fonte de negócio

**Especificar** → `specs/dbt/staging.md`

**Produtizar**
- `stg_{fonte}_orders.sql` por fonte de negócio — inclui geocodificação CEP → município
- `stg_ibge_localidades.sql`, `stg_ibge_censo.sql`
- `stg_bcb_pix.sql`
- `schema.yml` com testes: `not_null` + `unique` em toda PK
- `sources.yml` com freshness por source

---

### Feature 5 — dbt Intermediate

**Explorar**
- Validar joins entre staging models
- Verificar cardinalidade (1:N, N:N)
- Validar cobertura municipal após geocodificação das fontes de negócio

**Entender**
- Documentar regras de negócio dos joins
- Definir schema comum das fontes de negócio: `município/mês + total_pedidos + receita + ticket_medio`
- Documentar premissas de gap temporal entre fontes (ex: Censo 2022 vs dados Olist 2015–2018)

**Especificar** → `specs/dbt/intermediate.md`

**Produtizar**
- `int_{fonte}_por_municipio.sql` — padroniza cada fonte de negócio para schema comum
- `int_municipios_enriquecidos.sql` — join de todas as covariáveis municipais
- `int_periodo_pre_pos.sql` — define janelas do experimento
- A partir daqui o pipeline é agnóstico à fonte de negócio
- `schema.yml` com testes de relacionamento

---

### Feature 6 — dbt Marts

**Explorar**
- Validar modelo intermediate com queries analíticas
- Verificar se as métricas fazem sentido de negócio
- Identificar o que o Streamlit vai precisar consumir

**Entender**
- Documentar definição de cada métrica
- Definir quais colunas são expostas para consumo

**Especificar** → `specs/dbt/marts.md`

**Produtizar**
- `mart_municipios.sql` — perfil completo por município
- `mart_geo_lift.sql` — dataset preparado para o experimento
- `schema.yml` com testes completos
- `schema.yml` com `meta` de owner e descrição de colunas

---

### Feature 7 — Qualidade com Elementary

**Explorar**
- Instalar Elementary e conectar ao BigQuery
- Entender quais anomalias detecta automaticamente
- Ver o dashboard gerado

**Entender**
- Definir quais monitores ativar por modelo
- Definir thresholds de anomalia de volume

**Produtizar**
- Configurar Elementary no `packages.yml` do dbt
- Ativar monitores de volume, freshness e schema
- Integrar alerta no GitHub Actions

---

### Feature 8 — CI/CD GitHub Actions

**Produtizar** (sem exploração necessária)
- `ci.yml` — pytest + dbt compile + dbt test + terraform plan (todo PR)
- `deploy.yml` — build Docker + push + deploy Cloud Run (merge na main)

---

### Feature 9 — Streamlit

**Explorar**
- Prototipar visualizações em notebook
- Entender o que conta melhor a história do dado

**Entender**
- Definir as 3 visualizações principais
- Definir filtros e interatividade necessários

**Especificar** → `specs/streamlit/dashboard.md`

**Produtizar**
- Mapa de municípios com covariáveis (Plotly)
- Distribuição de métricas por região e fonte de negócio
- Comparação de perfil entre regiões candidatas

---

## Ordem de Construção

```
Documentação
1. README + escopo
2. ADRs
3. docs/conventions.md + docs/sources.md + docs/data_quality.md

--- Local A — sem dependência de cloud ---
4.  Feature 1 — Ingestão Olist           (4a: Parquet local)
5.  Feature 2 — Ingestão IBGE            (4a: Parquet local)
6.  Feature 3 — Ingestão BCB PIX         (4a: Parquet local)
7.  Feature 4 — dbt Staging              (4a: dbt contra arquivos locais)
8.  Feature 5 — dbt Intermediate         (4a: dbt contra arquivos locais)
9.  Feature 6 — dbt Marts               (4a: dbt contra arquivos locais)
10. Feature 7 — Qualidade com Elementary (4a)

--- Local B — dbt contra BigQuery ---
11. Features 1–7                         (4b: mesmos scripts, dbt → BigQuery)

--- Preparação para remoto ---
12. Terraform — provisiona infraestrutura GCP
13. Feature 8 — CI/CD GitHub Actions

--- Remoto — GCP em produção ---
14. Features 1–7                         (4c: Cloud Run + GCS + BigQuery)
15. Feature 9 — Streamlit

Documentação final
16. Documentar prompts Claude Code usados
```

> O Terraform entra só quando o pipeline está validado no Local B — você já sabe exatamente o que precisa provisionar.
> Fontes de enriquecimento e v2 documentadas em `docs/roadmap.md`.

---

## Convenções

### Nomenclatura dbt
- staging: `stg_{fonte}_{entidade}` — ex: `stg_olist_orders`
- intermediate: `int_{descricao}` — ex: `int_orders_por_municipio`
- marts: `mart_{entidade}` — ex: `mart_geo_lift`

### Nomenclatura BigQuery
- datasets: `{ambiente}_{dominio}` — ex: `prod_olist`, `dev_ibge`
- tabelas: snake_case sempre

### Nomenclatura GCS
- `raw/{fonte}/year=X/month=X/day=X/data.parquet`

### Commits semânticos
- `feat:` nova funcionalidade
- `fix:` correção de bug
- `refactor:` sem mudança de comportamento
- `test:` adição ou correção de testes
- `docs:` documentação
- `chore:` manutenção

---

## Política de Qualidade

### Testes obrigatórios — todo modelo dbt

| Contexto | Teste |
|---|---|
| Toda PK | `not_null` + `unique` |
| Toda FK | `relationships` |
| Campos de status | `accepted_values` |
| Campos numéricos de negócio | `expression_is_true (> 0)` |

### Freshness obrigatória — toda source

```yaml
freshness:
  warn_after:  {count: 1, period: day}
  error_after: {count: 3, period: day}
```

### Catálogo obrigatório — staging e marts
- `description` em todo modelo e toda coluna
- `meta.owner` em todo modelo
- `tags` de domínio

---

## SLAs das Fontes — v1

| Fonte | Frequência | SLA | Tolerância |
|---|---|---|---|
| Olist | Carga batch única | — | — |
| IBGE — Localidades | Estável (base referencial) | — | — |
| IBGE — Censo 2022 | Decenal (referência 2022) | — | — |
| BCB — PIX | Mensal | Dia 15 do mês seguinte | 3 dias |

> Fontes de enriquecimento (BCB IFData, Anatel SCM, IBGE Malhas) estão no roadmap v2/v3. Ver `docs/roadmap.md`.

---

## CLAUDE.md — Harness do Projeto

O arquivo `CLAUDE.md` na raiz define o contexto persistente para o Claude Code:

```markdown
## Sobre o projeto
Pipeline de Analytics Engineering para Geo Lift
usando dados públicos brasileiros no GCP.

## Ciclo de desenvolvimento
Toda feature de produção segue: Explorar → Entender → Especificar → Produtizar.
Antes de gerar código de produção, leia a spec correspondente em /specs.

## Stack
Python 3.11, dbt Core, BigQuery, GCS, Streamlit, Terraform

## Convenções obrigatórias
- Pydantic para validação de schema em toda ingestão
- Tenacity para retry em toda chamada de API
- Logging estruturado com structlog
- Nunca hardcodar credenciais — usar variáveis de ambiente
- Commits semânticos

## Testes obrigatórios
- not_null + unique em toda PK
- Teste unitário cobrindo edge cases da spec
```

---

## Custo Estimado GCP

| Serviço | Custo |
|---|---|
| BigQuery | Gratuito até 1TB/mês |
| Google Cloud Storage | < R$ 5/mês |
| Cloud Run | Gratuito até 2M requests/mês |
| Cloud Scheduler | Gratuito até 3 jobs |
| **Total** | **~R$ 0 a R$ 10/mês** |

---

## ADR-001: BigQuery como Warehouse

**Status:** Aceito

**Decisão:** Usar BigQuery como warehouse principal.

**Justificativa:**
- Integração nativa com GCS — carga direta sem ETL adicional
- Serverless — sem cluster para gerenciar
- Free tier de 1TB/mês suficiente para portfólio
- Integração nativa com Looker Studio e Streamlit
- Padrão do mercado brasileiro em empresas de produto digital

**Alternativas descartadas:**
- Snowflake — multi-cloud irrelevante para stack GCP, custo maior
- Cloud Spanner — OLTP, não OLAP
- Redshift — fora do escopo GCP

**Consequências:**
- Stack limitada ao ecossistema GCP — aceitável para portfólio
- Atenção a custos em tabelas grandes — usar particionamento e preview

---

## ADR-002: Cloud Run + Cloud Scheduler para Ingestão em Produção

**Status:** Aceito

**Decisão:** Cloud Run para execução e Cloud Scheduler para agendamento em produção.

**Justificativa:**
- Serverless — não paga quando não executa
- Containerizado — reproduzível localmente e em produção
- Cloud Scheduler gratuito até 3 jobs
- Flexível para scripts com dependências complexas

**Alternativas descartadas:**
- Cloud Composer — ~$300/mês, inviável para portfólio
- Prefect Cloud — boa opção mas fora do ecossistema GCP nativo
- Compute Engine — paga mesmo ocioso

**Consequências:**
- Sem interface visual de DAGs em produção — monitoramento via Cloud Logging
- Compatível com Airflow local — mesmos scripts, orquestrador diferente

---

## ADR-003: Parquet como Formato da Raw Layer

**Status:** Aceito

**Decisão:** Parquet como padrão, JSONL como fallback para schemas variáveis.

**Justificativa:**
- Colunar — queries no BigQuery leem só colunas necessárias
- Compressão eficiente — menor custo de storage
- Suporte nativo no BigQuery
- Preserva tipos — evita problemas de casting no staging

**Alternativas descartadas:**
- CSV — sem tipos nativos, problemas com caracteres especiais
- Avro — ótimo para streaming, desnecessário para batch

---

## ADR-004: Airflow Local como Orquestrador de Desenvolvimento

**Status:** Supersedida pela ADR-006

**Decisão original:** Airflow via Docker Compose localmente. Cloud Scheduler em produção.

**Por que foi supersedida:** após exploração das fontes, todos os datasets de negócio confirmaram-se históricos estáticos. Sem incrementalidade real, o principal valor do Airflow (`execution_date`, `catchup`, janelas temporais) desaparece. Ver ADR-006.

---

## ADR-005: Fontes de Negócio como Categoria Genérica e Plugável

**Status:** Aceito

**Decisão:** Tratar as fontes de negócio como uma categoria genérica e plugável — não como uma fonte específica. Qualquer dataset que chegue no formato padronizado pode alimentar o experimento.

**Justificativa:**
- O problema de negócio é genérico — medir causalidade em expansão geográfica de produto digital
- Amarrar o pipeline ao Olist tornaria o projeto uma análise específica, não uma plataforma
- A separação entre fontes de negócio e covariáveis municipais torna a arquitetura reusável

**Consequências arquiteturais:**
- Staging resolve o problema específico de cada fonte (ex: geocodificação CEP → município)
- Intermediate padroniza todas as fontes para schema comum: `municipio_id / ano_mes / total_pedidos / receita_total / ticket_medio / fonte`
- A partir do intermediate o pipeline é agnóstico à fonte de negócio
- Premissas de integração documentadas por fonte na spec correspondente

**Alternativas descartadas:**
- Olist como fonte única — reduz reusabilidade e limita argumento de portfólio
- Schema livre até o mart — inviabiliza construção agnóstica do experimento

---

## ADR-006: Remoção do Airflow — Substituição por Makefile

**Status:** Aceito
**Supersede:** ADR-004

**Decisão:** Remover o Airflow. Substituir por Makefile para orquestração local. Produção (Cloud Scheduler + Cloud Run) permanece inalterada.

**Justificativa:**
- Todos os datasets de negócio confirmaram-se históricos estáticos após exploração
- Sem incrementalidade real, o valor central do Airflow (`execution_date`, `catchup`, janelas temporais) desaparece
- O que restaria seria um cron job com dependências — o Makefile entrega isso sem complexidade adicional
- Usar Airflow sem problema real que justifique é overengineering documentado

**O que substitui localmente:**
```makefile
pipeline:
    python ingestion/src/olist.py
    python ingestion/src/ibge_localidades.py
    python ingestion/src/ibge_censo.py
    python ingestion/src/bcb_pix.py
    python ingestion/src/bcb_ifdata.py
    dbt run && dbt test
```

**Compatibilidade com produção:**
```
Local              Produção
Makefile           Cloud Scheduler
    ↓                  ↓
python script.py   Cloud Run Job
    ↓                  ↓
   mesmo script Python
```

**Consequências:**
- Feature 8 (Airflow) removida do roadmap
- `airflow/` e `specs/airflow/` removidos do repositório
- A ausência do Airflow é uma decisão documentada — não uma lacuna
