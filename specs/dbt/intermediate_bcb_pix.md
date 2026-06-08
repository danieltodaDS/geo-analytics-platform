# Spec — dbt Intermediate BCB PIX (Feature 5 — parcial)

> Pré-requisito: `stg_bcb_pix` fechado e testes passando.
> Fase coberta: **4a — Local A** (dbt-duckdb).
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da camada

```
O que chega:    stg_bcb_pix — 1 linha por (municipio_ibge, ano_mes)
O que muda:     Agregação mensal → 1 linha por município; derivação de métricas totais
O que NÃO muda: Filtro temporal — responsabilidade do mart
Grain final:    1 linha por municipio_ibge
```

---

## Visão geral

```
int_bcb_pix_por_municipio
└── stg_bcb_pix
```

---

## Modelo: int_bcb_pix_por_municipio

**Responsabilidade:** agregar os meses disponíveis de transações PIX para 1 linha por município, produzindo métricas de volume e cobertura temporal usadas como covariável no mart de geo lift.

**Grain:** 1 registro por `municipio_ibge`.

**Fonte:** `stg_bcb_pix`.

### Colunas descartadas do staging

| Coluna | Motivo |
|---|---|
| `municipio`, `estado`, `estado_ibge`, `sigla_regiao`, `regiao` | Labels geográficos duplicados de `int_ibge_municipios` — chave de join é `municipio_ibge` |
| `row_hash` | Fingerprint técnico de dedup — sem valor analítico |

### Colunas do modelo

| Coluna | Tipo | Lógica |
|---|---|---|
| `municipio_ibge` | BIGINT | PK — chave de join com `int_ibge_municipios` |
| `primeiro_ano_mes` | INTEGER | `MIN(ano_mes)` — início da cobertura temporal |
| `ultimo_ano_mes` | INTEGER | `MAX(ano_mes)` — fim da cobertura temporal |
| `qt_meses` | BIGINT | `COUNT(DISTINCT ano_mes)` — meses com dado; proxy de cobertura |
| `vl_total_enviado` | DOUBLE | `SUM(vl_pagador_pf + vl_pagador_pj)` — valor total enviado pelo município (R$) |
| `vl_total_recebido` | DOUBLE | `SUM(vl_recebedor_pf + vl_recebedor_pj)` — valor total recebido pelo município (R$) |
| `qt_total_transacoes` | DOUBLE | `SUM(qt_pagador_pf + qt_pagador_pj)` — total de transações como pagador |
| `qt_pes_pagador_total` | DOUBLE | `SUM(qt_pes_pagador_pf + qt_pes_pagador_pj)` — soma de participantes mensais como pagador |

> **Limite de `qt_pes_*`:** os campos `qt_pes_*` no BCB representam participantes únicos *por mês*. O `SUM` entre meses infla o número — um participante ativo em 12 meses conta 12 vezes. Esta coluna é útil como proxy de atividade agregada, mas NÃO deve ser interpretada como "total de pessoas únicas". O mart deve documentar esse limite ou derivar uma média mensal (`qt_pes_pagador_total / qt_meses`) se preferir normalização temporal.

### Enviado vs. recebido

Cada registro no BCB representa o município como agente de ambos os lados:
- `vl_pagador_*` = saídas financeiras do município (residentes/empresas enviando PIX)
- `vl_recebedor_*` = entradas financeiras do município (residentes/empresas recebendo PIX)

As duas métricas **não são double-counting** — representam fluxos distintos. Para matching de geo lift, `vl_total_enviado` é o proxy mais limpo de capacidade de consumo digital da população local.

**PK:** `municipio_ibge` — `not_null` + `unique`.

**Testes adicionais:**

| Teste | Condição |
|---|---|
| `expression_is_true` | `vl_total_enviado > 0` |
| `expression_is_true` | `qt_total_transacoes > 0` |
| `expression_is_true` | `qt_meses > 0` |
| `expression_is_true` | `primeiro_ano_mes <= ultimo_ano_mes` |

---

## O que esta spec não cobre

- Filtro por janela temporal de referência (ex: meses pré-período do experimento) — responsabilidade do mart
- Série temporal mensal para DiD — `stg_bcb_pix` já tem o grão correto; consumir diretamente no mart se necessário
- Normalização de `qt_pes_*` por população — responsabilidade do mart, requer join com `int_ibge_municipios`

---

*Spec fechada em: Junho/2026*
