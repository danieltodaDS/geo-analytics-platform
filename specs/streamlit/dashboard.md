# Spec — Streamlit Dashboard

> Feature 9 — fase 4a (DuckDB local)
> Understanding: `docs/understanding/streamlit.md`

---

## Escopo

Aplicação Streamlit com uma aba única: seleção de município + matching por Mahalanobis + comparativo visual de covariáveis.

Fase 4a: DuckDB local. Fase 4b: mesma lógica, conexão substituída por BigQuery.

---

## Fonte de dados

```python
duckdb.connect("dbt/geo_analytics.duckdb", read_only=True)
# tabela: marts.mart_geo_analytics
```

---

## Conjunto de matching

**Covariáveis (6):**

| Coluna | Papel |
|---|---|
| `populacao_residente` | Escala do mercado |
| `renda_media_per_capita` | Poder de compra |
| `pct_domicilios_com_internet` | Infraestrutura digital |
| `penetracao_olist` | Adoção de e-commerce |
| `ticket_medio` | Tamanho do ticket médio |
| `pct_pagamento_cartao` | Acesso a crédito |

**Filtragem:** `df.dropna(subset=FEATURES)` — sem imputação. Resultado esperado: ~2.874 municípios (89,4% do total).

**Matriz de covariância:** calculada uma vez sobre o conjunto completo ao inicializar o app.

---

## Algoritmo de matching

```python
from scipy.spatial.distance import cdist
import numpy as np

# Calculados uma vez na inicialização do app (fora de qualquer função reativa)
X = df_match[FEATURES].values                   # array alinhado com df_match
VI = np.linalg.inv(np.cov(X.T))

def get_top_matches(municipio_id: int, k: int = 5) -> pd.DataFrame:
    # Localiza o índice numérico no array X via posição no df_match reset
    pos = df_match.index.get_loc(
        df_match.index[df_match['id_municipio'] == municipio_id][0]
    )
    x_trat = X[pos].reshape(1, -1)
    distancias = cdist(x_trat, X, metric='mahalanobis', VI=VI).flatten()

    result = df_match.copy()           # nunca mutar o DataFrame global
    result['distancia'] = distancias
    return result[result['id_municipio'] != municipio_id].nsmallest(k, 'distancia')
```

Matching com reposição (um município pode ser par de múltiplos tratados).
k=5 fixo na fase 4a.

---

## Classificação de similaridade por match

Cada um dos 5 pares recebe uma classificação individual baseada na distância relativa à mediana das distâncias do município tratado:

```
ratio = distancia_match / mediana(todas_as_distancias_do_tratado)
```

| ratio | Classificação | Cor |
|---|---|---|
| < 0.30 | Muito parecido | Verde |
| 0.30 – 0.70 | Razoavelmente parecido | Amarelo |
| ≥ 0.70 | Pouco parecido | Vermelho |

**Calibração empírica (200 municípios):**
- p50 do ratio top5: 0.22 → a maioria dos municípios tem pelo menos um par "muito parecido"
- SP (outlier nacional): top1=0.46 (razoável), top2–5=0.77–0.81 (pouco) — sinaliza corretamente que SP é único
- Municípios pequenos: ratios 0.13–0.32 → maioria "muito parecido", espelha a realidade

**A classificação é por match, não por município.** O decisor vê a qualidade de cada par individualmente — os 5 pares são sempre exibidos, com badges coloridos indicando a qualidade de cada um.

---

## Painel de covariáveis

**Visualização:** small multiples — um gráfico de barras por covariável, 2 colunas × 2 linhas.

**4 covariáveis exibidas (das 6 de matching):**

| Covariável | Justificativa |
|---|---|
| `populacao_residente` | Mais imediata — escala do mercado |
| `renda_media_per_capita` | Poder de compra |
| `pct_domicilios_com_internet` | Infraestrutura digital |
| `penetracao_olist` | Liga o perfil ao negócio |

**Destaque visual:** município tratado em azul escuro (`#1f77b4`), pares em azul claro (`#aec7e8`).

**Escala:** zero-based em todos os gráficos (`rangemode='tozero'`). Barras sem zero-base exageram diferenças visuais e enganam o decisor.

**`ticket_medio` e `pct_pagamento_cartao`:** usadas no matching, não exibidas no painel visual. Sem expander na fase 4a — escopo mínimo.

---

## Dropdown de seleção

- Opções no formato `"Nome do Município - UF"` — evita ambiguidade com homônimos (ex: São Domingos existe em GO, BA, PB e SC)
- Ordenado alfabeticamente por nome
- Busca por texto nativa do Streamlit (`st.selectbox`)
- Valor mapeado internamente para `id_municipio` (código IBGE 7 dígitos)

---

## Layout da aba

```
┌─────────────────────────────────────────────────────────┐
│ Selecione o município:  [dropdown — formato "Nome - UF"] │
├─────────────────────────────────────────────────────────┤
│ Municípios mais similares                                │
│                                                          │
│  # │ Município          │ UF │ Similaridade              │
│  1 │ Fortaleza          │ CE │ 🟢 Muito parecido         │
│  2 │ Manaus             │ AM │ 🟢 Muito parecido         │
│  3 │ Belo Horizonte     │ MG │ 🟡 Razoavelmente parecido │
│  4 │ Goiânia            │ GO │ 🟡 Razoavelmente parecido │
│  5 │ Recife             │ PE │ 🟡 Razoavelmente parecido │
│                                                          │
├─────────────────────────────────────────────────────────┤
│ Comparativo de covariáveis                               │
│                                                          │
│  [populacao_residente]      [renda_media_per_capita]     │
│  ████ ░░░ ░░░ ░░░ ░░░ ░░░  ████ ░░░ ░░░ ░░░ ░░░ ░░░    │
│                                                          │
│  [pct_domicilios_internet]  [penetracao_olist]           │
│  ████ ░░░ ░░░ ░░░ ░░░ ░░░  ████ ░░░ ░░░ ░░░ ░░░ ░░░    │
└─────────────────────────────────────────────────────────┘
```

---

## Edge cases

| Situação | Comportamento |
|---|---|
| Município sem `pct_pagamento_cartao` ou `ticket_medio` | Aviso: "Este município não está disponível para matching por ausência de covariáveis completas." Não exibir pares. |
| Município com todos os pares "Pouco parecido" | Exibir normalmente com badges vermelhos — não omitir. O decisor precisa ver o sinal de alerta. |
| Dropdown vazio / sem seleção | Estado inicial: instrução "Selecione um município para ver os pares." |

---

## Arquivo de implementação

`streamlit/app.py` — arquivo único na fase 4a.

---

## Débitos técnicos para fase 4b

- Conexão DuckDB → BigQuery (`google.cloud.bigquery`)
- Cache do Streamlit (`@st.cache_data`) para a matriz VI e o DataFrame base, que em 4a são rápidos mas em 4b têm latência de rede

---

*Atualizado: 2026-06-09*
