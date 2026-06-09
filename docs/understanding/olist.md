# Understanding — Olist

> Resultado da exploração em `exploration/olist_exploration.ipynb`.
> Base para a spec em `specs/ingestion/olist.md`.

---

## Fonte e formato

Dataset público do Kaggle — carga batch única de CSVs estáticos. Sem API, sem paginação, sem autenticação. O script de ingestão lê os CSVs locais e grava um Parquet por tabela.

---

## Tabelas e volume

| Tabela | Linhas | Colunas |
|---|---|---|
| `olist_customers_dataset.csv` | 99.441 | 5 |
| `olist_geolocation_dataset.csv` | 1.000.163 | 5 |
| `olist_order_items_dataset.csv` | 112.650 | 7 |
| `olist_order_payments_dataset.csv` | 103.886 | 5 |
| `olist_order_reviews_dataset.csv` | 99.224 | 7 |
| `olist_orders_dataset.csv` | 99.441 | 8 |
| `olist_products_dataset.csv` | 32.951 | 9 |
| `olist_sellers_dataset.csv` | 3.095 | 4 |

---

## Schema por tabela

**customers**
| Campo | Tipo |
|---|---|
| `customer_id` | str |
| `customer_unique_id` | str |
| `customer_zip_code_prefix` | int64 |
| `customer_city` | str |
| `customer_state` | str |

**orders**
| Campo | Tipo | Nulos |
|---|---|---|
| `order_id` | str | — |
| `customer_id` | str | — |
| `order_status` | str | — |
| `order_purchase_timestamp` | str | — |
| `order_approved_at` | str | 160 |
| `order_delivered_carrier_date` | str | 1.783 |
| `order_delivered_customer_date` | str | 2.965 |
| `order_estimated_delivery_date` | str | — |

> Campos de data chegam como string no CSV e são mantidos como string no raw. Cast para datetime é responsabilidade do staging dbt. Campos com nulos terão `Optional[str]` no Pydantic.

**order_items**
| Campo | Tipo |
|---|---|
| `order_id` | str |
| `order_item_id` | int64 |
| `product_id` | str |
| `seller_id` | str |
| `shipping_limit_date` | str |
| `price` | float64 |
| `freight_value` | float64 |

**order_payments**
| Campo | Tipo |
|---|---|
| `order_id` | str |
| `payment_sequential` | int64 |
| `payment_type` | str |
| `payment_installments` | int64 |
| `payment_value` | float64 |

**geolocation**
| Campo | Tipo |
|---|---|
| `geolocation_zip_code_prefix` | int64 |
| `geolocation_lat` | float64 |
| `geolocation_lng` | float64 |
| `geolocation_city` | str (lowercase) |
| `geolocation_state` | str |

> A tabela tem 1.000.163 linhas para ~19.015 zip prefixes distintos (~52 registros por prefix). As duplicatas são consequência do truncamento do CEP para 5 dígitos por privacidade: um prefix cobre múltiplos endereços com lat/lng distintos. Não é anomalia — é comportamento esperado da fonte. Deduplicação (ex: centroide ou primeiro registro por prefix) é responsabilidade do staging dbt.

**sellers**
| Campo | Tipo |
|---|---|
| `seller_id` | str |
| `seller_zip_code_prefix` | int64 |
| `seller_city` | str |
| `seller_state` | str |

**products**
| Campo | Tipo | Nulos |
|---|---|---|
| `product_id` | str | — |
| `product_category_name` | str | 610 |
| demais atributos físicos | float64 | 610 / 2 |

---

## Nulos relevantes

| Tabela | Campo | Nulos | Tratamento |
|---|---|---|---|
| `orders` | `order_approved_at` | 160 | Aceitar — pedidos não aprovados |
| `orders` | `order_delivered_carrier_date` | 1.783 | Aceitar — pedidos não entregues ao carrier |
| `orders` | `order_delivered_customer_date` | 2.965 | Aceitar — pedidos não entregues ao cliente |
| `products` | `product_category_name` | 610 | Aceitar — produtos sem categoria |
| `order_reviews` | `review_comment_*` | ~58k–87k | Aceitar — review sem texto é válido |

Nulos em `orders` são esperados: pedidos cancelados, em processamento ou não entregues não terão todas as datas preenchidas.

---

## Período coberto

- **Início:** 2016-09-04
- **Fim:** 2018-10-17
- **2016:** 329 pedidos (setembro–dezembro apenas — dataset incompleto para esse ano)
- **2017:** 45.101 pedidos
- **2018:** 54.011 pedidos

**Decisão:** usar 2017–2018 como período de análise. 2016 tem volume residual e cobertura parcial.

---

## Status dos pedidos

| Status | Quantidade |
|---|---|
| `delivered` | 96.478 (97,0%) |
| `shipped` | 1.107 |
| `canceled` | 625 |
| `unavailable` | 609 |
| outros | 622 |

Para o mart_geo_analytics, usar apenas pedidos com `order_status = 'delivered'` — são os únicos com transação efetivamente concluída.

---

## Estratégia de geocodificação

**Problema:** o dataset não tem código IBGE. A unidade de análise do geo lift é o município (código IBGE 7 dígitos).

**Caminho disponível:**
```
customer_zip_code_prefix (5 dígitos)
  → geolocation table → (city, state) em lowercase
    → normalização → join com IBGE localidades → id_municipio (7 dígitos)
```

**Cobertura:**
- 99,0% dos zip prefixes de customers cobertos pela geolocation
- Apenas 0,3% dos pedidos (278 de 99.441) ficam sem cobertura — aceitável

**Risco:** matching por nome de cidade é suscetível a variações ortográficas entre datasets (ex: `sao paulo` vs `São Paulo`). A normalização deve remover acentos e converter para lowercase antes do join.

**Decisão:** esta estratégia é viável para o raw layer. A geocodificação em si (join city+state → IBGE) é responsabilidade do staging dbt — o raw layer grava os CSVs como Parquet sem transformação.

---

## Tabelas ingeridas

Todas as 8 tabelas são ingeridas para o raw layer. Nenhuma é descartada na ingestão — decisões de uso e filtragem são responsabilidade das camadas downstream.

| Tabela | Relevância para geo lift |
|---|---|
| `orders` | Pedidos com timestamp e vínculo ao customer |
| `order_items` | Valor por item (preço + frete) |
| `order_payments` | Valor total pago por pedido |
| `customers` | Zip code para geocodificação do comprador |
| `geolocation` | Ponte zip prefix → city/state → IBGE |
| `sellers` | Geocodificação do seller — pode alimentar análise de entrada em municípios |
| `products` | Categorias — enriquecimento opcional |
| `order_reviews` | Satisfação — fora do escopo direto do geo lift |

---

## Decisões para a spec

1. Script lê CSVs de `data/olist/` e grava um Parquet por tabela em `{RAW_BASE_PATH}/olist/{tabela}/`
2. Todas as 8 tabelas são ingeridas — nenhuma descartada no raw
3. Transformações permitidas no raw: apenas as necessárias para salvar Parquet (ex: inferência de tipos do pandas). Sem casts explícitos, sem filtragens, sem renomeações
4. Campos de data em `orders` mantidos como string — cast para datetime é responsabilidade do staging dbt
5. Campos nulos em `orders` (datas de entrega) passados como `Optional[str]` — tratamento downstream
6. Pedidos de todos os status mantidos no raw — filtragem por `delivered` é responsabilidade do staging
7. 2016 mantido no raw — corte temporal é responsabilidade do staging
8. Duplicatas em `geolocation` mantidas no raw — deduplicação é responsabilidade do staging
