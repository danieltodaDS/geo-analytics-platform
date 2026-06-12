# Spec — dbt Raw (Feature 4 — subcamada)

> Esta camada é o ponto de entrada do dbt no pipeline ELT.
> Ela não transforma dado — só o expõe no warehouse para as camadas downstream.
> Fase coberta: **4a — Local A** (dbt-duckdb).

---

## Contrato da camada

```
O que chega:    Parquets em data/raw/ (Phase 4a) ou dev_raw no BigQuery (Phase 4b+)
O que faz:      Expõe o dado bruto como relação endereçável pelo dbt
O que NÃO faz:  Nenhuma transformação — nem renomeação, nem cast, nem filtro
Granularidade:  Idêntica ao Parquet — 1 linha raw = 1 linha raw model
Materialização: view (Phase 4a — sem duplicação de dado)
Schema dbt:     raw
Testes:         Nenhum — critério de promoção é a view ser queryável
Responsável:    dbt raw models + job de carga (bq load na Phase 4b)
```

A camada raw no dbt existe para que staging e downstream nunca referenciem
fontes externas diretamente. Em Phase 4a a fonte é o Parquet via `external_location`;
em Phase 4b é o `dev_raw` do BigQuery. O que muda entre fases é apenas
a configuração de fonte em `_sources.yml` — todos os modelos downstream
(`{{ ref('olist_orders') }}` etc.) continuam inalterados.

---

## Modelos

Um modelo por tabela raw. Nenhum prefixo — o nome do modelo é igual ao nome
da tabela no Parquet/dev_raw.

| Modelo | Fonte | Schema Parquet |
|---|---|---|
| `olist_customers` | `data/raw/olist_customers/` | customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state |
| `olist_orders` | `data/raw/olist_orders/` | order_id, customer_id, order_status, datas (VARCHAR), ... |
| `olist_order_items` | `data/raw/olist_order_items/` | order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value |
| `olist_order_payments` | `data/raw/olist_order_payments/` | order_id, payment_sequential, payment_type, payment_installments, payment_value |
| `olist_order_reviews` | `data/raw/olist_order_reviews/` | review_id, order_id, review_score, comentários (VARCHAR), datas (VARCHAR) |
| `olist_geolocation` | `data/raw/olist_geolocation/` | geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state |
| `olist_products` | `data/raw/olist_products/` | product_id, product_category_name, product_name_lenght (typo), dimensões físicas |
| `olist_sellers` | `data/raw/olist_sellers/` | seller_id, seller_zip_code_prefix, seller_city, seller_state |
| `ibge_localidades` | `data/raw/ibge_localidades/` | id_municipio, nome_municipio, hierarquia geográfica completa |
| `ibge_censo_9606` | `data/raw/ibge_censo_9606/` | NC, NN, MC, MN, V, D1C–D6C, D1N–D6N (chaves internas SIDRA) |
| `ibge_censo_9605` | `data/raw/ibge_censo_9605/` | NC, NN, MC, MN, V, D1C–D4C, D1N–D4N (4 dimensões; D5/D6 NULL) |
| `ibge_censo_9514` | `data/raw/ibge_censo_9514/` | NC, NN, MC, MN, V, D1C–D6C, D1N–D6N (chaves internas SIDRA) |
| `bcb_pix` | `data/raw/bcb_pix/` | AnoMes, Municipio_Ibge, Municipio, Estado_Ibge, Estado, Sigla_Regiao, Regiao, VL_*/QT_* (PascalCase) |

Todos os modelos incluem as colunas de partição `year`, `month`, `day` — elas são
descartadas apenas no staging.

---

## Configuração de fonte (Phase 4a)

Declarada em `models/raw/_sources.yml`. Source name: `parquet_files`.

```yaml
sources:
  - name: parquet_files
    tables:
      - name: olist_customers
        meta:
          external_location: "read_parquet('../data/raw/olist_customers/**/*.parquet')"
```

O glob `**/*.parquet` cobre qualquer partição `year=/month=/day=/` presente.
O path é relativo ao diretório `dbt/` onde os comandos dbt são executados.

### Migração Phase 4b

Substituir `_sources.yml` por sources apontando para `dev_raw` no BigQuery:

```yaml
sources:
  - name: raw
    database: <gcp_project>
    schema: dev_raw
    tables:
      - name: olist_customers
      # sem external_location — BigQuery resolve a tabela nativamente
```

Os modelos raw (`select * from {{ source(...) }}`) não precisam de alteração.
Os modelos staging e downstream também não mudam.

---

## SQL dos modelos

Cada modelo é um `SELECT *` simples:

```sql
select * from {{ source('parquet_files', '<tabela>') }}
```

Não há lógica, CTE, alias de coluna nem filtro. Qualquer adição aqui é violação
do contrato da camada.

---

## Testes

Nenhum teste dbt nesta camada. O critério de promoção é a view ser criada sem
erro pelo `dbt run`. Erros de schema ou tipo são responsabilidade da ingestão
(Pydantic) — não da camada raw.

---

## O que esta spec não cobre

- Renomeação de colunas → staging
- Cast de tipos → staging
- Qualquer transformação → staging ou superior
- Deduplicação → intermediate
- Regras de negócio → intermediate / marts

---

*Spec fechada em: Junho/2026*
