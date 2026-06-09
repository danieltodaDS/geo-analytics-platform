# Backlog — Desenvolvimentos Futuros

> Pré-requisito: v1 em produção (local + remoto).
> Os itens abaixo são **independentes entre si** — não há ordem obrigatória.
> Cada um segue o ciclo Explorar → Entender → Especificar → Produtizar do CLAUDE.md.

---

## 1. Inferência Causal

**Objetivo:** medir o impacto de uma campanha de expansão geográfica com maior robustez, comparando múltiplas técnicas. A campanha pode ser real (data de entrada do produto por município) ou simulada com dados sintéticos quando não há evento real disponível.

### Por que não A/B Test simples

Comparações ingênuas introduzem três vieses:

- **Viés temporal:** crescimento orgânico e sazonalidade afetam todas as regiões — não dá separar efeito do produto do efeito do tempo com antes/depois simples.
- **Viés de seleção:** regiões que recebem o produto primeiro tendem a ser diferentes (mais ricas, mais digitalizadas). Comparar diretamente é comparar coisas diferentes.
- **Spillover:** em A/B por usuário, controle pode ser contaminado pelo tratamento. Regiões geográficas são naturalmente isoladas.

### Técnicas a explorar e comparar

| Técnica | Biblioteca | O que resolve |
|---|---|---|
| Diferença em Diferenças (DiD) | `statsmodels`, `linearmodels` | Viés temporal + estimativa de impacto |
| Propensity Score Matching | `sklearn` | Viés de seleção via probabilidade de tratamento |
| Geo Lift | pacote R `GeoLift` | Matching + DiD + teste de permutação integrados |

Avaliar robustez comparando resultados entre técnicas. Convergência entre métodos é evidência mais forte do que um único resultado.

> **Nota:** Geo Lift requer ambiente R separado (`renv` ou equivalente). As demais técnicas são Python puro.

### Covariáveis de matching

**Nível 1 — Contexto socioeconômico (disponível no mart_geo_analytics):**
- população, renda per capita, % domicílios com internet, volume PIX

**Nível 2 — Comportamento de e-commerce no pré-período:**
- volume de pedidos pré, ticket médio pré, categorias distintas, sazonalidade

O Nível 2 é o mais importante — comportamento passado é o preditor mais forte de comportamento futuro.

### Esboço de implementação — Matching

```python
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.neighbors import NearestNeighbors

features = ['populacao', 'renda_per_capita', 'pct_internet',
            'volume_pix', 'volume_pedidos_pre', 'ticket_medio_pre']

X = StandardScaler().fit_transform(df[features])

# 1. Calcular propensity score
lr = LogisticRegression()
lr.fit(X, df['grupo_binario'])
df['propensity_score'] = lr.predict_proba(X)[:, 1]

# 2. Parear cada tratado com o controle de score mais próximo (1D)
ps_trat = df.loc[df.grupo == 'tratamento', 'propensity_score'].values.reshape(-1, 1)
ps_ctrl = df.loc[df.grupo == 'controle',   'propensity_score'].values.reshape(-1, 1)

nn = NearestNeighbors(n_neighbors=1).fit(ps_ctrl)
_, indices = nn.kneighbors(ps_trat)

df_matched = pd.concat([
    df[df.grupo == 'tratamento'],
    df[df.grupo == 'controle'].iloc[indices.flatten()]
])
```

Critério de seleção: SMD < 0.1 em todas as covariáveis após matching.

### Esboço de implementação — DiD

```python
import statsmodels.formula.api as smf

# Formato longo: uma linha por (municipio, periodo)
# periodo_pos: 0 = pré, 1 = pós | tratamento: 0 = controle, 1 = tratado
# tratamento_pos: termo de interação — coeficiente é o lift causal

modelo = smf.ols(
    'metrica ~ tratamento + periodo_pos + tratamento:periodo_pos',
    data=df
).fit()

lift    = modelo.params['tratamento:periodo_pos']
p_value = modelo.pvalues['tratamento:periodo_pos']
ic_95   = modelo.conf_int().loc['tratamento:periodo_pos']
```

Validação obrigatória: tendências paralelas no pré-período.
Aplicar sobre `df_matched` após Propensity Score Matching para estimativa ajustada.

### Dados sintéticos

Se não houver campanha real, simular tratamento com atribuição aleatória estratificada por perfil de município. Permite testar e comparar técnicas com ground truth conhecido.

### Como iniciar

1. Explorar: inspecionar `mart_geo_analytics`, verificar cobertura temporal e distribuição de covariáveis
2. Definir grupos (tratamento/controle) — por data de entrada do produto ou atribuição sintética
3. Especificar → `specs/ds/inferencia_causal.md`
4. Sequência sugerida (Python):
   - DiD simples sem matching — baseline; valida tendências paralelas e produz estimativa inicial
   - Propensity Score Matching → selecionar pares → reaplicar DiD sobre `df_matched`
   - Comparar os dois resultados: a diferença indica o grau de viés de seleção
5. Geo Lift (R) como contraste independente — montar ambiente R separado (`renv`); rodar após as técnicas Python para validação cruzada dos resultados

> Covariáveis adicionais do item 4 (CAGED, Anatel SCM) enriquecem o matching — quanto mais rico o Nível 1, mais preciso o pareamento.

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

