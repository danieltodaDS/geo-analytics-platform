# Geo Analytics Platform — Roadmap

> Este documento preserva o raciocínio completo de todas as fases do projeto.
> Quando for iniciar cada fase, releia do início — as decisões aqui foram pensadas
> no contexto da fase anterior já construída e em produção.

---

## Visão Geral

```
Fase 1 — v1 (foco atual)
Analytics Engineering completo — local + remoto em produção
Fontes: Olist + IBGE Localidades + Censo 2022 + BCB PIX
Mart: mart_geo_lift pronto para o modelo causal

Fase 2 — v2
Data Science (matching + DiD) + enriquecimento de fontes + agentes

Fase 3 — Futuro
Itens exploratórios e de baixa prioridade
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
- `mart_geo_lift` — unidade municipal, métricas de negócio + covariáveis prontas para o modelo causal

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
- Ingestão via Cloud Run Jobs
- Orquestração via Cloud Scheduler
- Parquet no GCS → BigQuery — raw → staging → intermediate → mart
- IaC via Terraform provisionado
- CI/CD via GitHub Actions ativo

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
- `mart_geo_lift.sql` — dataset final com métricas + covariáveis
- `schema.yml` — suite completa de testes + descrições de colunas + owner

---

#### Feature 7 — Qualidade com Elementary

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

#### Feature 8 — CI/CD GitHub Actions

**Produtizar** (sem exploração necessária)
- `ci.yml` — pytest + dbt compile + dbt test + terraform plan (todo PR)
- `deploy.yml` — build Docker + push Artifact Registry + deploy Cloud Run (merge na main)

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
- Comparação de perfil entre regiões candidatas

---

### Ordem de Construção — v1

```
Documentação
1. README + escopo
2. ADRs
3. docs/conventions.md + docs/sources.md + docs/data_quality.md

--- Local A — sem dependência de cloud ---
4.  Feature 1 — Ingestão Olist           (4a: Parquet local)
5.  Feature 2 — Ingestão IBGE            (4a: Parquet local)
6.  Feature 3 — Ingestão BCB PIX         (4a: Parquet local)
7.  Feature 4 — dbt Staging              (4a: dbt-duckdb)
8.  Feature 5 — dbt Intermediate         (4a: dbt-duckdb)
9.  Feature 6 — dbt Marts               (4a: dbt-duckdb)
10. Feature 7 — Qualidade com Elementary (4a)
11. Feature 9 — Streamlit                (4a: protótipo local contra DuckDB)

--- Local B — dbt contra BigQuery ---
12. Features 4–6                         (4b: migração de dialeto dbt-duckdb → dbt-bigquery)
13. Feature 7 — Elementary               (4b: contra BigQuery)
14. Feature 9 — Streamlit                (4b: Streamlit → BigQuery)

--- Preparação para remoto ---
15. Terraform — provisiona infraestrutura GCP
16. Feature 8 — CI/CD GitHub Actions

--- Remoto — GCP em produção ---
17. Features 1–7                         (4c: Cloud Run + GCS + BigQuery)
18. Feature 9 — Streamlit                (4c: deploy final)

Documentação final
16. Documentar prompts Claude Code usados
```

> O Terraform entra só quando o pipeline está validado no Local B — você já sabe exatamente o que precisa provisionar.

---

## Fase 2 — v2

### Pré-requisito

v1 em produção — local + remoto funcionando de ponta a ponta.

### Escopo da v2

**Data Science — modelo causal:**
Usar o `mart_geo_lift` da v1 para medir o impacto causal da expansão do produto.

**Enriquecimento de fontes:**
- CAGED (Base dos Dados) — movimentações mensais de emprego formal por município
- RAIS (Base dos Dados) — vínculos anuais de emprego formal por município
- Segunda fonte de negócio — confirmar disponibilidade (ex: Shopee Brasil no Kaggle)

**Agentes:**
- Agente de Análise do Experimento
- Agente de Qualidade Narrativa

---

### Por que Geo Lift e não A/B Test simples

Comparações ingênuas introduzem três vieses:

**Viés temporal:** crescimento orgânico, sazonalidade e contexto econômico afetam todas as regiões — não dá separar o efeito do produto do efeito do tempo com antes/depois simples.

**Viés de seleção:** regiões que receberam o produto primeiro tendem a ser diferentes — mais ricas, mais urbanas, mais digitalizadas. Comparar diretamente é comparar coisas diferentes.

**Spillover:** em A/B tests por usuário, o grupo controle pode ser influenciado pelo tratamento. Regiões geográficas são naturalmente isoladas.

O Geo Lift resolve os três: **matching estatístico** elimina o viés de seleção, **Diferença em Diferenças (DiD)** elimina o viés temporal, e o **isolamento geográfico** elimina o spillover.

---

### Definição dos Grupos

```python
# Municípios com entrada de sellers antes de 2017-06 = tratamento
# Municípios com entrada depois = controle
df['grupo'] = np.where(
    df['data_primeira_venda'] < '2017-06-01',
    'tratamento',
    'controle'
)
```

---

### Covariáveis de Matching — Dois Níveis

**Nível 1 — Contexto socioeconômico (IBGE + BCB PIX):**
- população, IDH, renda per capita, % domicílios com internet, volume PIX

**Nível 2 — Comportamento de e-commerce (Olist pré-período):**
- volume de pedidos pré, ticket médio pré, categorias distintas pré, sazonalidade

O Nível 2 é o mais importante — comportamento passado é o preditor mais forte de comportamento futuro.

**Com CAGED e RAIS (v2):**
- formalidade econômica, setores dominantes, variação de emprego
- Enriquece o Nível 1 com dimensão de mercado de trabalho

---

### Algoritmo de Matching

Duas opções a avaliar durante a exploração:

**KNN (K-Nearest Neighbors):**
```python
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import NearestNeighbors

features = ['populacao', 'renda_per_capita', 'pct_internet',
            'volume_pix', 'volume_pedidos_pre', 'ticket_medio_pre']

scaler = StandardScaler()
X = scaler.fit_transform(df[features])

nn = NearestNeighbors(n_neighbors=1)
nn.fit(X[df.grupo == 'controle'])
distances, indices = nn.kneighbors(X[df.grupo == 'tratamento'])
```

**Propensity Score Matching:**
```python
from sklearn.linear_model import LogisticRegression

lr = LogisticRegression()
lr.fit(X, df['grupo_binario'])
df['propensity_score'] = lr.predict_proba(X)[:, 1]
```

Avaliar qual produz grupos mais balanceados via standardized mean difference (SMD < 0.1 em todas as covariáveis).

---

### Diferença em Diferenças

```python
tratamento_delta = (
    df[df.grupo=='tratamento']['metrica_pos'].mean() -
    df[df.grupo=='tratamento']['metrica_pre'].mean()
)

controle_delta = (
    df[df.grupo=='controle']['metrica_pos'].mean() -
    df[df.grupo=='controle']['metrica_pre'].mean()
)

lift = tratamento_delta - controle_delta
```

**Validação obrigatória:** tendências paralelas no pré-período.
**Teste de significância:** bootstrap ou teste t.

---

### Agente de Análise do Experimento

O mais diferenciado do projeto — não tem equivalente em ferramentas consolidadas.

```
mart_geo_lift disponível no BigQuery
       ↓
Agente lê os resultados
       ↓
Roda análise estatística (via tool use)
       ↓
Interpreta resultados no contexto do negócio
       ↓
Gera relatório em linguagem natural:
"O produto gerou lift de 12% em municípios urbanos
 com IDH > 0.7, mas não foi significativo em
 municípios rurais. Hipótese: penetração de
 internet insuficiente nas regiões de controle rural."
```

```python
import anthropic

client = anthropic.Anthropic()

def agente_analise(resultados: dict):
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=1000,
        tools=[{
            "name": "query_bigquery",
            "description": "Executa query analítica no BigQuery",
            "input_schema": {
                "type": "object",
                "properties": {"query": {"type": "string"}}
            }
        }],
        messages=[{
            "role": "user",
            "content": f"""
                Analise os resultados do experimento Geo Lift: {resultados}
                Investigue no BigQuery se necessário.
                Gere relatório interpretando o lift por segmento
                e proponha hipóteses para os resultados.
            """
        }]
    )
    return response
```

---

### Agente de Qualidade Narrativa

Complementa o Elementary — não substitui.

```
Elementary detecta: "volume de pedidos caiu 35% em SP"
       ↓
Agente investiga contexto:
- Queda isolada em SP ou geral?
- Categoria específica ou todas?
- Feriado ou sazonalidade conhecida?
       ↓
Agente reporta:
"Queda de 35% em SP isolada — outras regiões normais.
 Ocorreu em 02/11 (Finados). Provável sazonalidade,
 não incidente de pipeline."
```

---

### Ciclo de Desenvolvimento — v2

```
Explorar
└── Inspecionar mart_geo_lift
└── Testar diferentes datas de corte
└── Verificar balanceamento inicial dos grupos
└── Explorar CAGED e RAIS via Base dos Dados

Entender
└── Documentar distribuição das covariáveis
└── Identificar possíveis confundidores
└── Avaliar contribuição de CAGED/RAIS para o matching

Especificar
└── specs/ds/matching.md
└── specs/ds/did.md
└── specs/ingestion/caged.md
└── specs/ingestion/rais.md
└── specs/agents/analise_experimento.md
└── specs/agents/qualidade_narrativa.md

Produtizar
└── analysis/matching.py
└── analysis/experiment.py
└── ingestion/src/caged.py
└── ingestion/src/rais.py
└── agents/analysis_agent.py
└── agents/quality_agent.py
└── Integrar resultados e insights no Streamlit
```

---

### Entregável da v2

Streamlit atualizado com:
- Visualização dos grupos matched (tratamento vs controle)
- Gráfico de tendências paralelas (pré-período)
- Resultado do lift com intervalo de confiança
- Painel de insights dos agentes

---

## Fase 3 — Futuro

### O que entra aqui

Itens com potencial mas sem prioridade definida. Avaliados oportunisticamente após v2.

| Item | Descrição |
|---|---|
| BCB IFData | Densidade financeira e bancarização por município |
| Anatel SCM | Penetração de internet fixa por município |
| IBGE Malhas | Polígonos municipais para visualização cartográfica |
| PNAD TIC | % domicílios com internet por UF |
| BCB SGS | Séries macroeconômicas nacionais |
| Anatel Cobertura Móvel | Cobertura 3G/4G/5G por município (requer geoprocessamento) |
| Terceira fonte de negócio | Outros datasets de e-commerce ou produto digital |
| LangGraph | Agentes com fluxos multi-step mais complexos |

---

## Sequência Completa

```
FASE 1 — v1: Geo Analytics Platform
├── Local A: ingestão + dbt completos sem cloud
├── Local B: mesmos scripts, dbt → BigQuery
├── Terraform + CI/CD
├── Remoto: Cloud Run + GCS + BigQuery em produção
├── Streamlit — visualização dos dados preparados
└── v1 em produção local + GCP ← critério de conclusão

FASE 2 — v2
├── Data Science: matching + DiD
├── Enriquecimento: CAGED + RAIS
├── Segunda fonte de negócio
├── Agente de Análise do Experimento
├── Agente de Qualidade Narrativa
└── Streamlit atualizado com resultados + insights

FASE 3 — Futuro
└── Fontes e features de baixa prioridade ou exploratórias
```
