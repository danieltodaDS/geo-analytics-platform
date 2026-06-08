# Spec — dbt Staging (Feature 4)

> Pré-requisitos: specs de ingestão (olist, ibge, bcb_pix) fechadas e todos os Parquets disponíveis em `data/raw/`.
> Fase coberta: **4a — Local A** (dbt-duckdb contra Parquets locais).
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da camada

```
O que chega:    Dado do dataset_raw (Phase 4a: Parquets locais)
O que muda:     Cast de tipos, renomeação para snake_case, remoção de colunas de partição,
                remoção de duplicatas técnicas (linhas byte-a-byte idênticas)
O que NÃO muda: Granularidade — 1 linha raw = 1 linha staging (após dedup técnica)
Regras:         NENHUMA regra de negócio — só limpeza técnica
                Sem filtros, sem joins, sem agregações, sem dedup semântica
Critério:       not_null nos identificadores-chave passando (ADR-008)
                unique não é testado em staging — garantido no intermediate
```

---

## Fonte dos dados (Phase 4a)

Declaradas em `models/staging/_sources.yml` via `meta.external_location`.
Path relativo ao diretório `dbt/` onde os comandos são executados.

```yaml
meta:
  external_location: "read_parquet('../data/raw/{tabela}/**/*.parquet')"
```

Phase 4b: substituir por sources BigQuery (`dataset_raw`). Ajustes de dialeto esperados (ADR-007).

---

## Modelos e transformações

Todas as regras abaixo são **técnicas** — nenhuma implica decisão de negócio.

### Regra universal
Colunas de partição `year`, `month`, `day` são descartadas em todos os modelos.

---

### stg_olist_customers
- Sem transformações além da regra universal.
- **PK:** `customer_id` — `not_null` + `unique`

### stg_olist_orders
- Cast de todos os campos de data (`VARCHAR`) → `TIMESTAMP` via `TRY_CAST`.
- **PK:** `order_id` — `not_null` + `unique`

### stg_olist_order_items
- Cast de `shipping_limit_date` (`VARCHAR`) → `TIMESTAMP` via `TRY_CAST`.
- **PK composta:** `(order_id, order_item_id)` — surrogate key gerado como `order_id || '-' || order_item_id::VARCHAR`
- Teste: `not_null` + `unique` no surrogate.

### stg_olist_order_payments
- Sem transformações além da regra universal.
- **PK composta:** `(order_id, payment_sequential)` — surrogate `order_id || '-' || payment_sequential::VARCHAR`
- Teste: `not_null` + `unique` no surrogate.

### stg_olist_order_reviews
- Cast de `review_creation_date` e `review_answer_timestamp` (`VARCHAR`) → `TIMESTAMP` via `TRY_CAST`.
- **Anomalia do dataset:** `review_id` não é único no raw Olist — o mesmo `review_id` aparece vinculado a múltiplos `order_id` diferentes (mesmo texto de avaliação reutilizado em pedidos distintos). Descoberta durante testes.
- **PK composta:** `(review_id, order_id)` — surrogate `review_id || '-' || order_id`
- Teste: `not_null` + `unique` no surrogate `review_pk`; `not_null` em `review_id`.

### stg_olist_geolocation
- Sem transformações além da regra universal.
- Múltiplas linhas por zip code preservadas (dedup é responsabilidade do intermediate).
- **Teste mínimo:** `not_null` em `geolocation_zip_code_prefix`.
- Nota: não há PK única nesta tabela no nível staging — o unique é testado no intermediate após dedup.

### stg_olist_products
- Correção de typos técnicos nos nomes de coluna do CSV original:
  - `product_name_lenght` → `product_name_length`
  - `product_description_lenght` → `product_description_length`
- Join com tradução de categorias e filtros de status: responsabilidade do intermediate.
- **PK:** `product_id` — `not_null` + `unique`

### stg_olist_sellers
- Sem transformações além da regra universal.
- **PK:** `seller_id` — `not_null` + `unique`

### stg_ibge_localidades
- Cast de `microrregiao_id` e `mesorregiao_id` de `DOUBLE` → `INTEGER` (nullable — municípios pós-2017 não têm hierarquia antiga).
- **PK:** `id_municipio` — `not_null` + `unique`

### stg_ibge_censo_9606
Fonte: Domicílios com internet / Pop. residente — breakdown Sexo × Cor/Raça × Idade.

Renomeação de colunas SIDRA → nomes legíveis:

| Raw | Staging | Tipo |
|---|---|---|
| `D1C` | `codigo_municipio` | `BIGINT` via cast |
| `D2C` | `codigo_variavel` | `VARCHAR` |
| `D2N` | `variavel` | `VARCHAR` |
| `D3C` | `ano` | `BIGINT` via cast |
| `D4C` | `codigo_sexo` | `VARCHAR` |
| `D4N` | `sexo` | `VARCHAR` |
| `D5C` | `codigo_cor_raca` | `VARCHAR` |
| `D5N` | `cor_raca` | `VARCHAR` |
| `D6C` | `codigo_idade` | `VARCHAR` |
| `D6N` | `idade` | `VARCHAR` |
| `V`   | `valor` | `DOUBLE` via `TRY_CAST` (NULL preservado) |

Descartados: `NC`, `NN`, `MC`, `MN`, `D1N` (nome com UF sufixado, redundante com ibge_localidades), `D3N`.

Grain: `(codigo_municipio, codigo_variavel, codigo_sexo, codigo_cor_raca, codigo_idade)`

Surrogate: `md5(D1C || '|' || D2C || '|' || D4C || '|' || D5C || '|' || D6C)`

**Comportamento de NULL no surrogate:** o operador `||` propaga NULL — se qualquer componente for NULL, o surrogate inteiro vira NULL. O teste `not_null` no surrogate é o guardião: falha imediatamente se o dado vier com chave de dimensão nula. O IBGE não publica chaves nulas, então o risco é baixo; o teste existe para capturar defeitos de ingestão.

Testes: `not_null` + `unique` no surrogate; `not_null` em `codigo_municipio`.

### stg_ibge_censo_9605
Fonte: Rendimento médio domiciliar per capita — breakdown Cor/Raça.

Mesmo mapeamento que 9606, exceto:
- `D4C/D4N` → `codigo_cor_raca / cor_raca` (não sexo)
- Sem D5/D6 (tabela tem apenas 4 dimensões — D5C/D5N/D6C/D6N são NULL no raw e não são selecionados no staging)

Grain: `(codigo_municipio, codigo_variavel, codigo_cor_raca)`

Surrogate: `md5(D1C || '|' || D2C || '|' || D4C)` — mesmo comportamento de NULL descrito acima.

### stg_ibge_censo_9514
Fonte: População por Sexo × Forma de Declaração × Idade.

| Raw | Staging |
|---|---|
| `D4C/D4N` | `codigo_sexo / sexo` |
| `D5C/D5N` | `codigo_declaracao_idade / declaracao_idade` |
| `D6C/D6N` | `codigo_idade / idade` |

Grain: `(codigo_municipio, codigo_variavel, codigo_sexo, codigo_declaracao_idade, codigo_idade)`

Surrogate: `md5(D1C || '|' || D2C || '|' || D4C || '|' || D5C || '|' || D6C)` — mesmo comportamento de NULL descrito acima.

### stg_bcb_pix
Renomeação de PascalCase → snake_case:

| Raw | Staging | Tipo |
|---|---|---|
| `AnoMes` | `ano_mes` | `BIGINT` (formato YYYYMM — cast para DATE é responsabilidade do intermediate) |
| `Municipio_Ibge` | `municipio_ibge` | `BIGINT` |
| `Municipio` | `municipio` | `VARCHAR` |
| `Estado_Ibge` | `estado_ibge` | `BIGINT` |
| `Estado` | `estado` | `VARCHAR` |
| `Sigla_Regiao` | `sigla_regiao` | `VARCHAR` |
| `Regiao` | `regiao` | `VARCHAR` |
| `VL_PagadorPF` | `vl_pagador_pf` | `DOUBLE` |
| `QT_PagadorPF` | `qt_pagador_pf` | `BIGINT` |
| `VL_PagadorPJ` | `vl_pagador_pj` | `DOUBLE` |
| `QT_PagadorPJ` | `qt_pagador_pj` | `BIGINT` |
| `VL_RecebedorPF` | `vl_recebedor_pf` | `DOUBLE` |
| `QT_RecebedorPF` | `qt_recebedor_pf` | `BIGINT` |
| `VL_RecebedorPJ` | `vl_recebedor_pj` | `DOUBLE` |
| `QT_RecebedorPJ` | `qt_recebedor_pj` | `BIGINT` |
| `QT_PES_PagadorPF` | `qt_pes_pagador_pf` | `BIGINT` |
| `QT_PES_PagadorPJ` | `qt_pes_pagador_pj` | `BIGINT` |
| `QT_PES_RecebedorPF` | `qt_pes_recebedor_pf` | `BIGINT` |
| `QT_PES_RecebedorPJ` | `qt_pes_recebedor_pj` | `BIGINT` |

Grain: `(municipio_ibge, ano_mes)` — um registro por município por mês.

Surrogate: `municipio_ibge::VARCHAR || '-' || ano_mes::VARCHAR`

Testes: `not_null` + `unique` no surrogate; `not_null` em `municipio_ibge` e `ano_mes`.

---

## Testes por modelo

`unique` não é testado em staging (ADR-008). Apenas `not_null` nos identificadores mínimos.

| Modelo | Testes |
|---|---|
| stg_olist_customers | `not_null(customer_id)` |
| stg_olist_orders | `not_null(order_id)` |
| stg_olist_order_items | `not_null(order_item_pk)` |
| stg_olist_order_payments | `not_null(payment_pk)` |
| stg_olist_order_reviews | `not_null(review_id)` |
| stg_olist_geolocation | `not_null(geolocation_zip_code_prefix)` |
| stg_olist_products | `not_null(product_id)` |
| stg_olist_sellers | `not_null(seller_id)` |
| stg_ibge_localidades | `not_null(id_municipio)` |
| stg_ibge_censo_9606 | `not_null(surrogate_key)`, `not_null(codigo_municipio)` |
| stg_ibge_censo_9605 | `not_null(surrogate_key)`, `not_null(codigo_municipio)` |
| stg_ibge_censo_9514 | `not_null(surrogate_key)`, `not_null(codigo_municipio)` |
| stg_bcb_pix | `not_null(pix_pk)`, `not_null(municipio_ibge)`, `not_null(ano_mes)` |

---

## O que esta spec não cobre

- Deduplicação de geolocation por zip prefix → `intermediate`
- Filtro `order_status = 'delivered'` → `intermediate`
- Corte temporal 2017–2018 → `intermediate`
- Join olist_products com tradução de categorias → `intermediate`
- Cast de `ano_mes` (YYYYMM) para DATE → `intermediate`
- Join entre fontes e covariáveis → `intermediate`
- Geocodificação zip prefix → código IBGE município → `intermediate`
- Qualquer agregação ou métrica → `intermediate` / `marts`

---

*Spec fechada em: Junho/2026*
