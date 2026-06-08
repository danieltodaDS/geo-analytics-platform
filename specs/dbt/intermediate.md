# Spec — dbt Intermediate (Feature 5)

> Pré-requisito: camada staging fechada e todos os modelos staging passando testes.
> Fase coberta: **4a — Local A** (dbt-duckdb contra Parquets locais).
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da camada

```
O que chega:    Modelos staging limpos, tipados, sem duplicatas técnicas
O que muda:     Dedup semântica, joins entre entidades, agregações, enriquecimento
O que NÃO muda: Exposição ao consumidor final — isso é responsabilidade do mart
Filtros:        Nenhum filtro de status ou temporal aplicado aqui — responsabilidade do mart
Regras:         not_null + unique em toda PK
                Regras de negócio explícitas e documentadas nesta spec
Critério:       not_null + unique em toda PK passando
                relationships em toda FK
                accepted_values em booleanos/status
                expression_is_true (valor > 0) em métricas numéricas
```

---

## Visão geral dos modelos

Árvore de dependências — leitura de baixo para cima reflete a ordem de build:

```
int_fact_orders
├── stg_olist_orders
├── stg_olist_customers
├── int_olist_geolocation
│   └── stg_olist_geolocation
├── int_olist_order_payments_agg
│   └── stg_olist_order_payments
├── int_olist_order_items_agg
│   ├── stg_olist_order_items
│   └── stg_olist_products
└── int_olist_order_reviews_agg
    └── stg_olist_order_reviews

int_dim_customers  [consumida no mart — não referenciada por int_fact_orders]
├── stg_olist_customers
└── int_olist_geolocation

int_dim_sellers  [consumida no mart — não referenciada por int_fact_orders]
├── stg_olist_sellers
└── int_olist_geolocation

int_dim_products  [consumida no mart — não referenciada por int_fact_orders]
└── stg_olist_products
```

> `int_olist_geolocation` é nó compartilhado: alimenta `int_fact_orders`, `int_dim_customers` e `int_dim_sellers`. Deve ser buildado antes dos três. O dbt resolve essa ordem automaticamente via `ref()`.

---

## Modelos

### int_olist_geolocation

**Responsabilidade:** dedup semântica de `stg_olist_geolocation` — múltiplos pares lat/lng por `zip_code_prefix`.

**Regra de negócio:** para cada `zip_code_prefix`, calcular o centróide (média de `geolocation_lat` e `geolocation_lng`). `geolocation_city` e `geolocation_state`: valor mais frequente (moda via `MODE()`).

**Grain:** um registro por `zip_code_prefix`.

**PK:** `geolocation_zip_code_prefix` — `not_null` + `unique`.

---

### int_olist_order_payments_agg

**Responsabilidade:** agregar `stg_olist_order_payments` para o grão order — eliminar a cardinalidade 1:N entre orders e payments antes do join no fact.

**Grain:** um registro por `order_id`.

**Regra de negócio:** pivot por `payment_type`. Tipos conhecidos: `credit_card`, `boleto`, `voucher`, `debit_card`, `not_defined`.

| Coluna | Lógica |
|---|---|
| `credit_card_value` | `SUM(payment_value) FILTER (WHERE payment_type = 'credit_card')` |
| `credit_card_installments` | `MAX(payment_installments) FILTER (WHERE payment_type = 'credit_card')` |
| `boleto_value` | `SUM(payment_value) FILTER (WHERE payment_type = 'boleto')` |
| `voucher_value` | `SUM(payment_value) FILTER (WHERE payment_type = 'voucher')` |
| `debit_card_value` | `SUM(payment_value) FILTER (WHERE payment_type = 'debit_card')` |
| `not_defined_value` | `SUM(payment_value) FILTER (WHERE payment_type = 'not_defined')` |
| `total_payment_value` | `SUM(payment_value)` — soma de todos os tipos |
| `payment_types_count` | `COUNT(DISTINCT payment_type)` — indica pagamento misto quando > 1 |

**Colunas excluídas:** `payment_sequential` — índice de aplicação por order, não propriedade do tipo. `installments` registrado apenas para `credit_card`; demais tipos não têm parcelamento.

**PK:** `order_id` — `not_null` + `unique`.

**Testes adicionais:** `expression_is_true (total_payment_value > 0)`.

---

### int_olist_order_items_agg

**Responsabilidade:** agregar `stg_olist_order_items` para o grão order — eliminar a cardinalidade 1:N entre orders e itens antes do join no fact.

**Grain:** um registro por `order_id`.

**Fontes:** `stg_olist_order_items` LEFT JOIN `stg_olist_products` ON `product_id` (para obter `product_category_name`).

**Regra de negócio:**

| Coluna | Lógica |
|---|---|
| `items_count` | `COUNT(order_item_id)` |
| `unique_products_count` | `COUNT(DISTINCT product_id)` |
| `unique_sellers_count` | `COUNT(DISTINCT seller_id)` |
| `total_price` | `SUM(price)` |
| `total_freight_value` | `SUM(freight_value)` |
| `total_revenue` | `SUM(price) + SUM(freight_value)` |
| `dominant_category_name` | `MODE(product_category_name)` — categoria mais frequente no pedido; NULL se todos os produtos sem categoria. Em empate entre categorias, resultado é não-determinístico (comportamento do `MODE()` no DuckDB/BigQuery) — débito técnico: avaliar se impacto em marts justifica regra de desempate explícita |

**PK:** `order_id` — `not_null` + `unique`.

**Testes adicionais:** `expression_is_true (items_count > 0)`, `expression_is_true (total_revenue > 0)`.

---

### int_olist_order_reviews_agg

**Responsabilidade:** agregar `stg_olist_order_reviews` para o grão order — alguns orders possuem mais de um review (mesmo `review_id` associado a múltiplos pedidos é a anomalia documentada no staging).

**Grain:** um registro por `order_id`.

**Regra de negócio:** para cada `order_id`, manter o review com o `review_answer_timestamp` mais recente. Em caso de empate de timestamp (edge case raro), o registro selecionado é não-determinístico — comportamento aceito.

| Coluna | Lógica |
|---|---|
| `review_score` | Score do review mais recente |
| `has_comment` | `review_comment_message IS NOT NULL` |
| `review_answer_timestamp` | Timestamp do review mantido |

**PK:** `order_id` — `not_null` + `unique`.

**Testes adicionais:** `accepted_values (review_score: [1, 2, 3, 4, 5])`, `not_null (review_score)`.

---

### int_dim_customers

**Responsabilidade:** dimensão de clientes reais com geolocalização canônica — resolve a ambiguidade entre `customer_id` (grão por pedido) e `customer_unique_id` (grão do cliente real).

**Grain:** um registro por `customer_unique_id`.

**Fontes:** `stg_olist_customers` GROUP BY `customer_unique_id`, LEFT JOIN `int_olist_geolocation` ON `customer_zip_code_prefix`.

**Regra de negócio:** um `customer_unique_id` pode ter múltiplos `customer_id` (um por pedido), podendo ter CEPs diferentes. Consolidar com moda (`MODE()`) em `customer_zip_code_prefix`, `customer_state` e `customer_city`. Lat/lng obtidos do centróide do CEP modal.

| Coluna | Lógica |
|---|---|
| `customer_unique_id` | PK — identificador real do cliente |
| `customer_zip_code_prefix` | `MODE(customer_zip_code_prefix)` |
| `customer_state` | `MODE(customer_state)` |
| `customer_city` | `MODE(customer_city)` |
| `customer_lat` | `geolocation_lat` do CEP modal (LEFT JOIN — NULL se CEP não encontrado) |
| `customer_lng` | `geolocation_lng` do CEP modal (LEFT JOIN — NULL se CEP não encontrado) |

**Consumidor:** mart — esta dimensão não é referenciada por `int_fact_orders`. Serve análises no grão cliente real (ex: frequência de compra, estado de origem do cliente).

**PK:** `customer_unique_id` — `not_null` + `unique`.

---

### int_dim_sellers

**Responsabilidade:** dimensão de vendedores enriquecida com geolocalização — `stg_olist_sellers` já é único por `seller_id`; este modelo apenas adiciona lat/lng via join.

**Grain:** um registro por `seller_id`.

**Fontes:** `stg_olist_sellers` LEFT JOIN `int_olist_geolocation` ON `seller_zip_code_prefix`.

| Coluna | Lógica |
|---|---|
| `seller_id` | PK |
| `seller_zip_code_prefix` | Direto do staging |
| `seller_state` | Direto do staging |
| `seller_city` | Direto do staging |
| `seller_lat` | `geolocation_lat` (LEFT JOIN — NULL se CEP não encontrado) |
| `seller_lng` | `geolocation_lng` (LEFT JOIN — NULL se CEP não encontrado) |

**PK:** `seller_id` — `not_null` + `unique`.

**Cobertura de geolocalização:** o join com `int_olist_geolocation` é LEFT JOIN intencional — sellers com CEP ausente na tabela de geolocalização terão `seller_lat`/`seller_lng` NULL. Monitorar a proporção de NULLs via métrica de qualidade no mart (meta: < 5% de sellers sem coordenadas).

---

### int_dim_products

**Responsabilidade:** dimensão de produtos com métrica de volume derivada — `stg_olist_products` já é único por `product_id`; este modelo adiciona `product_volume_cm3`.

**Grain:** um registro por `product_id`.

**Fontes:** `stg_olist_products`.

| Coluna | Lógica |
|---|---|
| `product_id` | PK |
| `product_category_name` | Direto do staging |
| `product_name_length` | Direto do staging |
| `product_description_length` | Direto do staging |
| `product_photos_qty` | Direto do staging |
| `product_weight_g` | Direto do staging |
| `product_length_cm` | Direto do staging |
| `product_height_cm` | Direto do staging |
| `product_width_cm` | Direto do staging |
| `product_volume_cm3` | `product_length_cm * product_height_cm * product_width_cm` — NULL se qualquer dimensão for NULL |

**PK:** `product_id` — `not_null` + `unique`.

---

### int_fact_orders

**Responsabilidade:** fato central no grão order — consolida todas as entidades Olist em um registro por pedido, com métricas de entrega derivadas. Nenhum filtro de `order_status` aplicado.

**Grain:** um registro por `order_id`.

**Fontes e joins:**

```
stg_olist_orders                          (base)
  INNER JOIN stg_olist_customers          ON order_id → customer_id   (resolve customer_unique_id e geografia do pedido)
  LEFT JOIN  int_olist_geolocation        ON customer_zip_code_prefix  (lat/lng do CEP do pedido)
  LEFT JOIN  int_olist_order_payments_agg ON order_id
  LEFT JOIN  int_olist_order_items_agg    ON order_id
  LEFT JOIN  int_olist_order_reviews_agg  ON order_id
```

> `stg_olist_customers` é INNER JOIN porque todo `order_id` deve ter um `customer_id` válido — ausência indica dado corrompido. Os demais são LEFT JOIN porque payments, items e reviews podem ter lacunas legítimas.

**Colunas:**

*Identificadores e status (de stg_olist_orders + stg_olist_customers):*

| Coluna | Fonte |
|---|---|
| `order_id` | PK |
| `customer_id` | stg_orders — identificador da transação |
| `customer_unique_id` | stg_customers — identificador do cliente real |
| `order_status` | stg_orders |

*Timestamps (de stg_olist_orders):*

| Coluna |
|---|
| `order_purchase_timestamp` |
| `order_approved_at` |
| `order_delivered_carrier_date` |
| `order_delivered_customer_date` |
| `order_estimated_delivery_date` |

*Geografia do pedido (CEP do cliente no momento do pedido):*

| Coluna | Fonte |
|---|---|
| `customer_zip_code_prefix` | stg_customers |
| `customer_state` | stg_customers |
| `customer_city` | stg_customers |
| `customer_lat` | int_olist_geolocation (LEFT JOIN) |
| `customer_lng` | int_olist_geolocation (LEFT JOIN) |

*Métricas derivadas de entrega:*

| Coluna | Lógica |
|---|---|
| `approval_days` | `date_diff('day', order_purchase_timestamp, order_approved_at)` — NULL se não aprovado |
| `estimated_delivery_days` | `date_diff('day', order_purchase_timestamp, order_estimated_delivery_date)` |
| `delivery_days` | `date_diff('day', order_purchase_timestamp, order_delivered_customer_date)` — NULL se não entregue |
| `is_on_time` | `order_delivered_customer_date <= order_estimated_delivery_date` — NULL se não entregue |

*Pagamentos (de int_olist_order_payments_agg):*

| Coluna |
|---|
| `total_payment_value` |
| `credit_card_value` |
| `credit_card_installments` |
| `boleto_value` |
| `voucher_value` |
| `debit_card_value` |
| `not_defined_value` |
| `payment_types_count` |

*Itens (de int_olist_order_items_agg):*

| Coluna |
|---|
| `items_count` |
| `unique_products_count` |
| `unique_sellers_count` |
| `total_price` |
| `total_freight_value` |
| `total_revenue` |
| `dominant_category_name` |

**Monitoramento de qualidade — `is_on_time`:** registros onde `order_delivered_customer_date IS NOT NULL AND order_status != 'delivered'` indicam dado inconsistente no source. Gerar estatística no mart: `COUNT(*) WHERE order_delivered_customer_date IS NOT NULL AND order_status != 'delivered'` — meta: 0 registros; qualquer valor positivo deve ser investigado.

*Reviews (de int_olist_order_reviews_agg, LEFT JOIN — NULL se sem review):*

| Coluna |
|---|
| `review_score` |
| `has_comment` |

**PK:** `order_id` — `not_null` + `unique`.

**Testes adicionais:**

| Teste | Coluna / Condição |
|---|---|
| `relationships` | `customer_id → stg_olist_customers.customer_id` |
| `accepted_values` | `order_status: [delivered, shipped, canceled, unavailable, invoiced, processing, created, approved]` |
| `expression_is_true` | `total_payment_value > 0` (quando não NULL) |
| `expression_is_true` | `items_count > 0` (quando não NULL) |
| `expression_is_true` | `approval_days >= 0` (quando não NULL) |
| `expression_is_true` | `delivery_days >= 0` (quando não NULL) |

---

## Débitos técnicos — riscos de dialeto para fase 4b (dbt-bigquery)

Os modelos abaixo usam funções DuckDB que **não existem com a mesma assinatura no BigQuery** e vão quebrar na migração da fase 4b:

| Função | Modelos afetados | Comportamento DuckDB | Equivalente BigQuery |
|---|---|---|---|
| `datediff('day', start, end)` | `int_fact_orders` | `end - start` em dias | `DATE_DIFF(end, start, DAY)` — argumentos em **ordem inversa** |
| `mode(expr)` | `int_olist_geolocation`, `int_dim_customers`, `int_olist_order_items_agg` | Agregado nativo | Não existe nativamente — requer `APPROX_TOP_COUNT(expr, 1)[OFFSET(0)].value` ou window function com `ROW_NUMBER()` |

**Ação na fase 4b:** substituir por macros `dbt_utils.datediff` e implementar macro própria `geo_analytics.mode_agg` com condicional `{% if target.type == 'bigquery' %}` para isolar o dialeto.

---

## O que esta spec não cobre (próximas iterações)

- Tradução de `product_category_name` PT → EN (arquivo `product_category_name_translation.csv` do dataset Olist)
- Linkage `zip_code_prefix` → código IBGE município (geocodificação reversa)
- Cast de `ano_mes` (YYYYMM BCB) para DATE
- `int_municipios_enriquecidos` — joins entre Olist, IBGE e BCB PIX no grão município
- `int_fact_order_items` — grão item, para análise por produto/categoria/vendedor

---

*Spec atualizada — Junho/2026*
