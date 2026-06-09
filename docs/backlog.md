# Backlog — Desenvolvimentos Futuros

> Pré-requisito: v1 em produção (local + remoto).
> Os itens abaixo são **independentes entre si** — não há ordem obrigatória.
> Cada um segue o ciclo Explorar → Entender → Especificar → Produtizar do CLAUDE.md.

---

## 1. Inferência Causal

**Objetivo:** medir o impacto de uma campanha de expansão geográfica com maior robustez, comparando múltiplas técnicas. A campanha pode ser real (data de entrada do produto por município) ou simulada com dados sintéticos quando não há evento real disponível.

> **Escopo na v1:** o Mahalanobis matching (etapa 1 da progressão abaixo) foi antecipado para a v1 como funcionalidade do Streamlit (Feature 9 do roadmap). DiD, PSM e Geo Lift permanecem como pós-v1.

### Por que não A/B Test simples

Comparações ingênuas introduzem três vieses:

- **Viés temporal:** crescimento orgânico e sazonalidade afetam todas as regiões — não dá separar efeito do produto do efeito do tempo com antes/depois simples.
- **Viés de seleção:** regiões que recebem o produto primeiro tendem a ser diferentes (mais ricas, mais digitalizadas). Comparar diretamente é comparar coisas diferentes.
- **Spillover:** em A/B por usuário, controle pode ser contaminado pelo tratamento. Regiões geográficas são naturalmente isoladas.

### Progressão de técnicas

A sequência vai do mais simples para o mais robusto. Cada etapa valida e alimenta a seguinte.

```
1. Mahalanobis matching      → define o grupo de controle
         ↓
2. DiD sobre os pares        → estima o lift causal
         ↓
3. PSM como matching alternativo → valida a robustez da seleção
         ↓
4. Geo Lift (R)              → contraste independente com teste de permutação
```

| Etapa | Técnica | Biblioteca | Papel |
|---|---|---|---|
| Matching 1 | Distância de Mahalanobis | `scipy` | Seleção de controles — simples, sem modelo |
| Estimativa | Diferença em Diferenças (DiD) | `statsmodels` | Lift causal com controle de tendência temporal |
| Matching 2 | Propensity Score Matching (PSM) | `sklearn` | Matching alternativo via modelo — valida robustez |
| Contraste | Geo Lift | pacote R `GeoLift` | Pipeline completo independente com permutação |

Convergência entre Mahalanobis+DiD e PSM+DiD é evidência de robustez da seleção. Convergência com Geo Lift é evidência de robustez da estimativa causal.

> **Nota:** Geo Lift requer ambiente R separado (`renv` ou equivalente). As demais técnicas são Python puro.

### Covariáveis de matching

6 variáveis fixadas — escolha baseada em correlação empírica verificada no `mart_geo_analytics`:

**Estruturais (contexto do município):**
- `populacao_residente` — escala do mercado
- `renda_media_per_capita` — poder de compra
- `pct_domicilios_com_internet` — infraestrutura digital

**Negócio (comportamento de e-commerce):**
- `penetracao_olist` — adoção de e-commerce por habitante (normalizada)
- `ticket_medio` — tamanho do ticket médio de compra
- `pct_pagamento_cartao` — acesso a crédito e formalização financeira

Correlações entre as 6 variáveis são todas baixas (|r| < 0.21) — sem redundância relevante. `avg_dias_entrega` foi descartada por correlação moderada com `pct_domicilios_com_internet` (-0.20) em favor de `pct_pagamento_cartao`, que captura uma dimensão independente.

> **Desalinhamento temporal:** `penetracao_olist`, `ticket_medio` e `pct_pagamento_cartao` são de 2018 (Olist); `renda_media_per_capita` e `pct_domicilios_com_internet` são de 2022 (Censo); `populacao_residente` é de 2022. O matching usa variáveis de períodos distintos como proxy do perfil estrutural do município — limitação herdada das fontes disponíveis, declarada em `docs/understanding/mart_geo_analytics.md`.

> Covariáveis adicionais do item 5 (CAGED, Anatel SCM) podem enriquecer o matching em versões futuras.

### Esboço de implementação — Matching por Mahalanobis

```python
import numpy as np
import pandas as pd
from scipy.spatial.distance import cdist

features = [
    'populacao_residente', 'renda_media_per_capita', 'pct_domicilios_com_internet',
    'penetracao_olist', 'ticket_medio', 'pct_pagamento_cartao'
]

df_trat = df[df.grupo == 'tratamento'][features]
df_ctrl = df[df.grupo == 'controle'][features]

# Mahalanobis usa a inversa da matriz de covariância do conjunto completo
VI = np.linalg.inv(np.cov(df[features].T))

distancias = cdist(df_trat, df_ctrl, metric='mahalanobis', VI=VI)

# Matching com reposição: um controle pode ser par de múltiplos tratados.
# Para DiD, ponderar controles pareados múltiplas vezes pelo número de usos.
indices_ctrl = distancias.argmin(axis=1)

df_matched = pd.concat([
    df[df.grupo == 'tratamento'].reset_index(drop=True),
    df[df.grupo == 'controle'].iloc[indices_ctrl].reset_index(drop=True)
])
```

Critério de qualidade do matching: SMD < 0.1 em todas as covariáveis após o pareamento.

### Esboço de implementação — Matching alternativo por PSM

```python
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.neighbors import NearestNeighbors

X = StandardScaler().fit_transform(df[features])

lr = LogisticRegression()
lr.fit(X, df['grupo_binario'])
df['propensity_score'] = lr.predict_proba(X)[:, 1]

ps_trat = df.loc[df.grupo == 'tratamento', 'propensity_score'].values.reshape(-1, 1)
ps_ctrl = df.loc[df.grupo == 'controle',   'propensity_score'].values.reshape(-1, 1)

nn = NearestNeighbors(n_neighbors=1).fit(ps_ctrl)
_, indices = nn.kneighbors(ps_trat)

df_matched_psm = pd.concat([
    df[df.grupo == 'tratamento'],
    df[df.grupo == 'controle'].iloc[indices.flatten()]
])
```

### Esboço de implementação — DiD

```python
import statsmodels.formula.api as smf

# Formato longo: uma linha por (municipio, periodo)
# periodo_pos: 0 = pré, 1 = pós | tratamento: 0 = controle, 1 = tratado
# tratamento:periodo_pos: termo de interação — coeficiente é o lift causal

modelo = smf.ols(
    'metrica ~ tratamento + periodo_pos + tratamento:periodo_pos',
    data=df_matched  # aplicar sobre df_matched ou df_matched_psm para comparar
).fit()

lift    = modelo.params['tratamento:periodo_pos']
p_value = modelo.pvalues['tratamento:periodo_pos']
ic_95   = modelo.conf_int().loc['tratamento:periodo_pos']
```

Validação obrigatória: tendências paralelas no pré-período antes de interpretar o coeficiente como causal.

### Dados sintéticos

Se não houver campanha real, simular tratamento com atribuição aleatória estratificada por perfil de município. Permite testar e comparar técnicas com ground truth conhecido.

### Como iniciar

1. Explorar: inspecionar `mart_geo_analytics`, verificar distribuição das 6 covariáveis
2. Definir grupos (tratamento/controle) — por data de entrada do produto ou atribuição sintética
3. Especificar → `specs/ds/inferencia_causal.md`
4. Sequência de implementação:
   - Mahalanobis matching → verificar SMD < 0.1 → DiD sobre os pares (baseline simples)
   - PSM → DiD sobre `df_matched_psm` — comparar com resultado anterior
   - Diferença entre os dois resultados indica sensibilidade à escolha do método de matching
5. Geo Lift (R) como contraste independente após as técnicas Python

---

## 2. Segmentação de Municípios

**Objetivo:** descobrir agrupamentos naturais de municípios com base em covariáveis socioeconômicas e de comportamento de e-commerce, sem label predefinida.

Casos de uso:
- Segmentação estratégica: identificar perfis recorrentes ("urbanos digitais", "rurais de baixa conectividade") para orientar expansão
- Benchmarking: comparar desempenho de um município dentro do seu segmento natural
- Análise exploratória: entender a heterogeneidade do território antes de modelar
- Insumo para inferência causal (item 1): segmentos como estrato para matching

### Algoritmos a explorar

| Algoritmo | Biblioteca | Característica |
|---|---|---|
| K-Means | `sklearn` | Segmentos com centróides interpretáveis; requer definir k |
| Hierarchical Clustering | `sklearn` | Dendrогrama — não precisa definir k a priori |
| DBSCAN | `sklearn` | Detecta outliers; bom para municípios atípicos |

KNN como ferramenta auxiliar de consulta ad hoc: dado um município específico, retorna os k mais similares para benchmarking pontual.

### Como iniciar

1. Definir quais covariáveis compõem o perfil municipal (Nível 1 do item 1 como base)
2. Explorar distribuição e escala das features — normalização obrigatória antes de qualquer algoritmo de distância
3. Experimentar K-Means com diferentes valores de k; avaliar coesão dos clusters (silhouette score)
4. Especificar → `specs/ds/segmentacao_municipios.md`

---

## 3. Agente de Análise

**Objetivo:** agente Claude que lê `mart_geo_analytics`, roda análise estatística via tool use e gera relatório interpretado em linguagem natural.

### Fluxo

```
mart_geo_analytics disponível no BigQuery
       ↓
Agente lê os dados (tool use → BigQuery)
       ↓
Roda análise estatística
       ↓
Interpreta resultados no contexto do negócio
       ↓
Relatório: lift por segmento + hipóteses explicativas
```

Exemplo de output:
> "O produto gerou lift de 12% em municípios urbanos com IDH > 0.7, mas não foi
> significativo em municípios rurais. Hipótese: penetração de internet insuficiente
> nas regiões de controle rural."

### Esboço de implementação

```python
import anthropic

client = anthropic.Anthropic()

def agente_analise(resultados: dict):
    return client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=2000,
        tools=[{
            "name": "query_bigquery",
            "description": "Executa query analítica no BigQuery",
            "input_schema": {
                "type": "object",
                "properties": {"query": {"type": "string"}},
                "required": ["query"]
            }
        }],
        messages=[{
            "role": "user",
            "content": f"""
                Analise os resultados do experimento causal: {resultados}
                Investigue no BigQuery se necessário.
                Gere relatório com: lift por segmento, significância estatística
                e hipóteses para os resultados encontrados.
            """
        }]
    )
```

### Como iniciar

1. Definir interface: quais inputs o agente recebe, qual o formato do output esperado
2. Especificar → `specs/agents/analise.md`
3. Implementar com Anthropic SDK; usar tool use para queries ao BigQuery

---

## 4. Agente de Qualidade Narrativa

**Objetivo:** complementa o Elementary — investiga contexto de anomalias detectadas e gera explicação em linguagem natural.

### Fluxo

```
Elementary detecta anomalia (ex: "volume de pedidos caiu 35% em SP")
       ↓
Agente investiga:
  - Queda isolada em SP ou geral?
  - Categoria específica ou todas?
  - Feriado ou sazonalidade conhecida?
       ↓
Agente reporta:
"Queda isolada em SP no dia 02/11 (Finados).
 Demais regiões e categorias normais.
 Provável sazonalidade, não incidente de pipeline."
```

### Como iniciar

1. Mapear quais alertas do Elementary chegam e em qual formato
2. Definir quais investigações o agente deve fazer automaticamente
3. Especificar → `specs/agents/qualidade_narrativa.md`

---

## 5. Fontes Adicionais de Covariáveis

Candidatas por relevância para matching causal — priorizar por relevância e facilidade de acesso:

| Fonte | Variável | Relevância | Acesso |
|---|---|---|---|
| CAGED (Base dos Dados) | Emprego formal mensal por município | Alta | API Base dos Dados |
| RAIS (Base dos Dados) | Vínculos anuais por município | Alta | API Base dos Dados |
| Anatel SCM | Internet fixa por município | Alta | Portal Anatel (download) |
| BCB IFData | Densidade financeira / bancarização | Média | API BCB |
| PNAD TIC | % domicílios com internet | Média | Granularidade UF, não município |
| Anatel Cobertura Móvel | 3G/4G/5G por município | Baixa | Requer geoprocessamento |
| IBGE Malhas | Polígonos municipais | Baixa | Só visualização cartográfica |
| BCB SGS | Séries macroeconômicas nacionais | Baixa | Granularidade nacional |

### Como iniciar qualquer fonte

Seguir o ciclo da v1: Explorar → Entender → `specs/ingestion/{fonte}.md` → Produtizar (script + Parquet + dbt staging).

---

## 6. Fontes Adicionais de Negócio

Segunda ou terceira fonte de negócio para ampliar o dataset de pedidos municipais e reduzir dependência do Olist.

Candidatas:
- Dataset de e-commerce brasileiro no Kaggle
- Qualquer dataset com `(municipio_id, data, valor)` municipalizável

Critérios mínimos: granularidade municipal, período mínimo de 12 meses, status de entrega disponível.

### Como iniciar

Seguir Feature 1 do `roadmap.md` como template — o pipeline já está desenhado para receber novas fontes de negócio plugáveis (ADR-005).

