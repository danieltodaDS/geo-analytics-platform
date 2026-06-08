# Spec — dbt Intermediate IBGE (Feature 6 — parcial)

> Pré-requisito: camada staging IBGE fechada (stg_ibge_localidades, stg_ibge_censo_9514, stg_ibge_censo_10295, stg_ibge_censo_9936).
> Fase coberta: **4a — Local A** (dbt-duckdb).
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da camada

```
O que chega:    4 modelos staging IBGE limpos, tipados, deduplicados tecnicamente
O que muda:     Pivot long→wide (stg_censo → 1 linha por município), join geografia+censo
O que NÃO muda: Exposição ao consumidor final — responsabilidade do mart
Filtros:        Nenhum filtro temporal ou geográfico — responsabilidade do mart
Regras:         not_null + unique em toda PK
```

---

## Visão geral dos modelos

```
int_ibge_municipios
├── stg_ibge_localidades
└── int_ibge_censo_covariaveis
    ├── stg_ibge_censo_9514
    ├── stg_ibge_censo_10295
    └── stg_ibge_censo_9936
```

---

## Modelos

### int_ibge_censo_covariaveis

**Responsabilidade:** pivotar as três tabelas SIDRA (formato long, N linhas por município) em um único modelo wide com 1 linha por município e 4 covariáveis do Censo 2022.

**Grain:** 1 registro por `codigo_municipio`.

**Fontes:** `stg_ibge_censo_9514`, `stg_ibge_censo_10295`, `stg_ibge_censo_9936`.

#### Por que descartar colunas dimensionais

As três tabelas foram ingeridas com `v/all/p/last` (9514, 10295) e com filtro de classificação `Total` (9936). Todas as dimensões secundárias (`sexo`, `idade`, `grupo_idade`, `cor_raca`, etc.) chegam com valor `"Total"` — não há breakdown real. Carregar essas colunas no intermediate seria ruído sem informação.

#### Seleção de variáveis por tabela

**9514 — População:**

| `codigo_variavel` | Nome | Coluna no intermediate | Manter? |
|---|---|---|---|
| `93` | População residente | `populacao_residente` | **Sim** — métrica absoluta para normalização |
| `1000093` | Pop. residente — % do total | — | Não — derivável, sem valor analítico incremental |

**10295 — Rendimento domiciliar:**

| `codigo_variavel` | Nome | Coluna no intermediate | Manter? |
|---|---|---|---|
| `13431` | Rendimento médio mensal domiciliar per capita | `renda_media_per_capita` | **Sim** — covariável geo lift |
| `13534` | Rendimento mediano mensal domiciliar per capita | `renda_mediana_per_capita` | **Sim** — covariável geo lift |
| `13604` | Moradores (contagem base) | — | Não — redundante com populacao_residente de 9514 |
| `1013604` | Moradores (% do total) | — | Não — derivável, sem valor analítico incremental |

**9936 — Internet:**

Já chega com 1 linha por município do staging. A coluna `pct_domicilios_com_internet` passa diretamente — nenhum pivot necessário.

#### Colunas do modelo

| Coluna | Tipo | Fonte | Lógica |
|---|---|---|---|
| `codigo_municipio` | BIGINT | 9514 base | PK |
| `ano_censo` | BIGINT | 9514 | `ano` — informativo, documentado para rastreabilidade |
| `populacao_residente` | DOUBLE | 9514 | `MAX(CASE WHEN codigo_variavel = '93' THEN valor END)` |
| `renda_media_per_capita` | DOUBLE | 10295 | `MAX(CASE WHEN codigo_variavel = '13431' THEN valor END)` |
| `renda_mediana_per_capita` | DOUBLE | 10295 | `MAX(CASE WHEN codigo_variavel = '13534' THEN valor END)` |
| `pct_domicilios_com_internet` | DOUBLE | 9936 | Direto do staging |

#### Estratégia de join

```
stg_ibge_censo_9514  (pivot GROUP BY codigo_municipio)   — base: 5.570 municípios
  LEFT JOIN stg_ibge_censo_10295 (pivot)  ON codigo_municipio
  LEFT JOIN stg_ibge_censo_9936           ON codigo_municipio
```

LEFT JOIN intencional: se um município existir em 9514 mas não em 10295 ou 9936, renda e internet ficam NULL em vez de sumir do modelo. Ausências devem ser monitoradas.

#### Nota de cobertura

9514 e 9936 retornam **5.570 municípios** (Censo 2022 não cobre Fernando de Noronha — distrito estadual). `stg_ibge_localidades` tem 5.571 municípios. O join em `int_ibge_municipios` (abaixo) produzirá 1 município sem covariáveis de censo — comportamento esperado, não erro.

**PK:** `codigo_municipio` — `not_null` + `unique`.

**Testes adicionais:**

| Teste | Condição |
|---|---|
| `expression_is_true` | `populacao_residente > 0` |
| `expression_is_true` | `renda_media_per_capita > 0` |
| `expression_is_true` | `renda_mediana_per_capita > 0` |
| `expression_is_true` | `pct_domicilios_com_internet > 0` |
| `expression_is_true` | `renda_mediana_per_capita <= renda_media_per_capita` — mediana ≤ média em distribuições de renda positivamente assimétricas; violação indica erro de mapeamento de variável |

---

### int_ibge_municipios

**Responsabilidade:** dimensão de municípios enriquecida — hierarquia geográfica completa da API de Localidades + covariáveis do Censo 2022 em 1 linha por município.

**Grain:** 1 registro por `id_municipio`.

**Fontes:** `stg_ibge_localidades` LEFT JOIN `int_ibge_censo_covariaveis` ON `id_municipio = codigo_municipio`.

#### Colunas do modelo

*Identificador:*

| Coluna | Tipo | Fonte |
|---|---|---|
| `id_municipio` | BIGINT | stg_ibge_localidades — PK |

*Localidade:*

| Coluna | Tipo | Fonte |
|---|---|---|
| `nome_municipio` | VARCHAR | stg_ibge_localidades |
| `uf_sigla` | VARCHAR | stg_ibge_localidades |
| `uf_nome` | VARCHAR | stg_ibge_localidades |
| `macroregiao_sigla` | VARCHAR | stg_ibge_localidades |
| `macroregiao_nome` | VARCHAR | stg_ibge_localidades |

Colunas descartadas do staging: IDs numéricos de hierarquia (`uf_id`, `macroregiao_id`) — substituídos por sigla/nome; hierarquias intermediárias (`regiao_imediata_*`, `regiao_interm_*`) — divisão IBGE 2017 sem uso no pipeline; hierarquia antiga (`microrregiao_*`, `mesorregiao_*`) — Optional na fonte, sem uso. Incluir se aparecer necessidade concreta no mart.

*Covariáveis censo (NULL para o município sem cobertura do Censo 2022):*

| Coluna | Tipo | Fonte |
|---|---|---|
| `ano_censo` | BIGINT | int_ibge_censo_covariaveis |
| `populacao_residente` | DOUBLE | int_ibge_censo_covariaveis |
| `renda_media_per_capita` | DOUBLE | int_ibge_censo_covariaveis |
| `renda_mediana_per_capita` | DOUBLE | int_ibge_censo_covariaveis |
| `pct_domicilios_com_internet` | DOUBLE | int_ibge_censo_covariaveis |

**PK:** `id_municipio` — `not_null` + `unique`.

**Testes adicionais:**

| Teste | Condição |
|---|---|
| `relationships` | `id_municipio → stg_ibge_localidades.id_municipio` |
| `not_null` | `nome_municipio`, `uf_sigla`, `uf_nome`, `macroregiao_sigla`, `macroregiao_nome` |

---

## O que esta spec não cobre

- Join `int_ibge_municipios` com Olist ou BCB PIX no grão município — responsabilidade do mart ou de um modelo `int_municipios_enriquecidos` futuro
- Breakdowns por sexo, faixa etária ou cor/raça — requer nova ingestão SIDRA com filtros explícitos de classificação

---

*Spec fechada em: Junho/2026*
