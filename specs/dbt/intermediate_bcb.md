# Spec — dbt Intermediate BCB PIX

> Fase coberta: **4a — Local A** (dbt-duckdb contra Parquets locais).
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da camada

```
O que chega:    stg_bcb_pix — PIX por município/mês, snake_case, sem duplicatas técnicas
O que muda:     Conversão de ano_mes (YYYYMM inteiro) → DATE; derivação de totais (pagador + recebedor)
O que NÃO muda: Granularidade — 1 linha por (municipio_ibge, ano_mes_data)
Filtros:        Nenhum — responsabilidade do mart
Dedup:          Não necessária — staging já garante unicidade na chave (municipio_ibge, ano_mes)
```

---

## Modelo

### int_bcb_pix_municipio

**Responsabilidade:** preparar dados PIX por município/mês para consumo no mart — converte o período YYYYMM em DATE e adiciona métricas de total (pagador + recebedor).

**Grain:** 1 registro por `(municipio_ibge, ano_mes_data)`.

**Fonte:** `stg_bcb_pix`.

#### Colunas

*Identificadores (PK composta):*

| Coluna | Tipo | Lógica |
|---|---|---|
| `municipio_ibge` | BIGINT | Código IBGE do município (7 dígitos) — FK para `int_ibge_municipios.id_municipio` |
| `ano_mes_data` | DATE | Primeiro dia do mês — `strptime(ano_mes::varchar, '%Y%m')::date` |

*Localização (denormalizado do staging para evitar join no mart):*

| Coluna | Tipo | Fonte |
|---|---|---|
| `municipio` | VARCHAR | Nome do município |
| `estado_ibge` | BIGINT | Código IBGE do estado (2 dígitos) |
| `estado` | VARCHAR | Nome do estado |
| `sigla_regiao` | VARCHAR | Sigla da macrorregião (N, NE, CO, SE, S) |
| `regiao` | VARCHAR | Nome da macrorregião |

*Métricas PIX — perspectiva pagador (fluxo de saída do município):*

| Coluna | Tipo | Lógica |
|---|---|---|
| `vl_pagador_pf` | DOUBLE | Valor enviado por pessoas físicas |
| `qt_pagador_pf` | BIGINT | Transações enviadas por PF |
| `vl_pagador_pj` | DOUBLE | Valor enviado por pessoas jurídicas |
| `qt_pagador_pj` | BIGINT | Transações enviadas por PJ |
| `vl_total_pagador` | DOUBLE | `vl_pagador_pf + vl_pagador_pj` — total de saída |
| `qt_total_transacoes_pagador` | BIGINT | `qt_pagador_pf + qt_pagador_pj` |
| `qt_pes_pagador_pf` | BIGINT | Pessoas físicas distintas que pagaram |
| `qt_pes_pagador_pj` | BIGINT | Pessoas jurídicas distintas que pagaram |

*Métricas PIX — perspectiva recebedor (fluxo de entrada no município):*

| Coluna | Tipo | Lógica |
|---|---|---|
| `vl_recebedor_pf` | DOUBLE | Valor recebido por pessoas físicas |
| `qt_recebedor_pf` | BIGINT | Transações recebidas por PF |
| `vl_recebedor_pj` | DOUBLE | Valor recebido por pessoas jurídicas |
| `qt_recebedor_pj` | BIGINT | Transações recebidas por PJ |
| `vl_total_recebedor` | DOUBLE | `vl_recebedor_pf + vl_recebedor_pj` — total de entrada |
| `qt_total_transacoes_recebedor` | BIGINT | `qt_recebedor_pf + qt_recebedor_pj` |
| `qt_pes_recebedor_pf` | BIGINT | Pessoas físicas distintas que receberam |
| `qt_pes_recebedor_pj` | BIGINT | Pessoas jurídicas distintas que receberam |

**PK:** composta `(municipio_ibge, ano_mes_data)`.

**Testes:**

| Teste | Coluna / Condição |
|---|---|
| `not_null` | `municipio_ibge`, `ano_mes_data` |
| `unique_combination_of_columns` | `[municipio_ibge, ano_mes_data]` |
| `relationships` | `municipio_ibge → int_ibge_municipios.id_municipio` |
| `expression_is_true` | `vl_total_pagador >= 0` |
| `expression_is_true` | `vl_total_recebedor >= 0` |
| `expression_is_true` | `qt_total_transacoes_pagador >= 0` |
| `expression_is_true` | `qt_total_transacoes_recebedor >= 0` |

---

## Débitos técnicos — dialeto para fase 4b (dbt-bigquery)

| Função | Comportamento DuckDB | Equivalente BigQuery |
|---|---|---|
| `strptime(ano_mes::varchar, '%Y%m')::date` | Converte YYYYMM → DATE | `PARSE_DATE('%Y%m', CAST(ano_mes AS STRING))` |

**Ação na fase 4b:** substituir por macro com condicional `{% if target.type == 'bigquery' %}`.

---

*Spec fechada em: Junho/2026*
