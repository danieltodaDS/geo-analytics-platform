# Understanding — Mart geo_analytics

> Resultado da exploração em `exploration/intermediate_exploration.ipynb`.
> Base para a spec em `specs/dbt/marts.md`.

---

## Volumes reais

| Tabela | Linhas |
|---|---|
| `int_bcb_pix_municipio` | 378.663 |
| `int_dim_customers` | 96.096 |
| `int_dim_products` | 32.951 |
| `int_dim_sellers` | 3.095 |
| `int_fact_orders` | 99.441 |
| `int_ibge_censo_covariaveis` | 5.570 |
| `int_ibge_municipios` | 5.571 |
| `int_olist_geolocation` | 19.015 (zip prefixes únicos) |
| `int_olist_order_items_agg` | 98.666 |
| `int_olist_order_payments_agg` | 99.440 |
| `int_olist_order_reviews_agg` | 98.673 |

> `int_fact_orders` (99.441) > `int_olist_order_items_agg` (98.666) e `int_olist_order_reviews_agg` (98.673): o fact usa LEFT JOIN — há pedidos sem items ou sem review.

---

## Schemas reais (colunas relevantes)

### int_fact_orders
| Coluna | Tipo | Nota |
|---|---|---|
| `order_id` | VARCHAR | PK |
| `customer_unique_id` | VARCHAR | FK → int_dim_customers |
| `order_status` | VARCHAR | ver distribuição abaixo |
| `order_purchase_timestamp` | TIMESTAMP | |
| `customer_zip_code_prefix` | BIGINT | ponte para geolocation |
| `customer_state` | VARCHAR | desnormalizado |
| `customer_city` | VARCHAR | desnormalizado |
| `customer_lat` / `customer_lng` | DOUBLE | da geolocation |
| `approval_days` | BIGINT | |
| `delivery_days` | BIGINT | |
| `is_on_time` | BOOLEAN | |
| `items_count` | BIGINT | de order_items_agg |
| `total_revenue` | DOUBLE | price + freight |
| `total_payment_value` | DOUBLE | de payments_agg |
| `review_score` | BIGINT | nullable — NULL se sem review |
| `has_comment` | BOOLEAN | nullable — 768 NULLs |

> Atenção: a spec `intermediate.md` chama de `total_items` mas a coluna real é `items_count`. Mesma discrepância potencial em `has_review` — o fact expõe `review_score IS NOT NULL` implicitamente, não uma coluna booleana `has_review`. O mart deve usar `review_score IS NOT NULL` ou `review_score`.

### int_olist_order_items_agg
| Coluna | Tipo |
|---|---|
| `order_id` | VARCHAR |
| `items_count` | BIGINT |
| `unique_products_count` | BIGINT |
| `unique_sellers_count` | BIGINT |
| `total_price` | DOUBLE |
| `total_freight_value` | DOUBLE |
| `total_revenue` | DOUBLE |
| `dominant_category_name` | VARCHAR |

### int_ibge_municipios
Inclui covariaveis desnormalizadas diretamente (resultado do JOIN com censo):

| Coluna | Tipo |
|---|---|
| `id_municipio` | BIGINT |
| `nome_municipio` / `uf_sigla` / `uf_nome` | VARCHAR |
| `macroregiao_sigla` / `macroregiao_nome` | VARCHAR |
| `ano_censo` | BIGINT |
| `populacao_residente` | DOUBLE |
| `renda_media_per_capita` | DOUBLE |
| `renda_mediana_per_capita` | DOUBLE |
| `pct_domicilios_com_internet` | DOUBLE |

> `int_ibge_municipios` já incorpora as covariáveis do censo — não é necessário fazer JOIN com `int_ibge_censo_covariaveis` no mart. As duas tabelas coexistem: `int_ibge_censo_covariaveis` é a versão normalizada (só covariáveis), `int_ibge_municipios` é a desnormalizada (geo + covariáveis).

---

## Distribuições e métricas Olist

### Order status
| Status | N | % |
|---|---|---|
| `delivered` | 96.478 | 97,0% |
| `shipped` | 1.107 | 1,1% |
| `canceled` | 625 | 0,6% |
| `unavailable` | 609 | 0,6% |
| outros | 622 | 0,6% |

**Decisão para o mart:** filtrar `order_status = 'delivered'` (96.478 pedidos).

### Cobertura temporal
| Ano | Pedidos | Receita |
|---|---|---|
| 2016 | 329 | R$ 57.183 |
| 2017 | 45.101 | R$ 7.142.672 |
| 2018 | 54.011 | R$ 8.643.698 |

**Decisão para o mart:** usar 2017–2018. 2016 tem cobertura parcial (set–dez) e volume residual (0,3%).

### Métricas agregadas (todos os pedidos)
| Métrica | Valor |
|---|---|
| Ticket médio | R$ 160,58 |
| Frete médio | R$ 22,82 |
| Itens por pedido (média) | 1,14 |
| Dias até aprovação (média) | 0,52 |
| Dias até entrega (média) | 12,5 |
| Entregues no prazo | 88.649 (89,1%) |
| Com review | 98.673 (99,2%) |

### Itens por pedido
| Itens | Pedidos |
|---|---|
| 1 | 88.863 (90,1%) |
| 2 | 7.516 |
| 3+ | 2.287 |

### Review scores
| Score | N | % |
|---|---|---|
| 5★ | 57.008 | 57,8% |
| 4★ | 19.038 | 19,3% |
| 3★ | 8.133 | 8,2% |
| 2★ | 3.131 | 3,2% |
| 1★ | 11.363 | 11,5% |

> Distribuição bimodal: 5★ (satisfação alta) e 1★ (frustração) são os dois grupos dominantes juntos.

### Reviews com comentário
| has_comment | N |
|---|---|
| `false` | 57.898 (58,5%) |
| `true` | 40.775 (41,3%) |
| NULL | 768 (0,8%) |

---

## Cobertura geográfica

### Customers com geolocation (ZIP → lat/lng)
| Total customers | Com geo | Cobertura |
|---|---|---|
| 96.096 | 95.827 | **99,72%** |

### Orders com geolocation (via customer ZIP)
| Total orders | Com geo | Cobertura |
|---|---|---|
| 99.441 | 99.163 | **99,72%** |

### Cross-domain: ZIP → município IBGE (via slug city+state match)
| Total pedidos (2017+) | Pedidos com município | Cobertura | Municípios distintos |
|---|---|---|---|
| 99.112 | 98.324 | **99,2%** | **4.009** |

> O join usa colunas `_slug` (sem acentos, snake_case) derivadas pela macro `normalize_city_name`: `geolocation_city_slug = nome_municipio_slug AND uf_sigla = geolocation_state`.
> Dos 5.571 municípios IBGE, **4.009 (72%)** têm ao menos um pedido Olist mapeado.
> Os 788 pedidos residuais (~0,8%) são bairros/distritos sem IBGE próprio (`goitacazes`, `papucaia`, `bonfim_paulista`) ou nomes históricos (`parati` → `Paraty`). Irresolúveis sem geocodificação externa.
>
> **Join antes da normalização (lower only):** 53% de cobertura — os 47% perdidos eram apenas acentos ausentes no Olist (`sao paulo` vs `São Paulo`).

### Orders por estado (top 10)
| UF | Pedidos | Receita |
|---|---|---|
| SP | 41.746 | R$ 5.921.678 |
| RJ | 12.852 | R$ 2.129.682 |
| MG | 11.635 | R$ 1.856.161 |
| RS | 5.466 | R$ 885.827 |
| PR | 5.045 | R$ 800.935 |
| BA | 3.380 | R$ 611.507 |
| SC | 3.637 | R$ 610.214 |
| DF | 2.140 | R$ 353.229 |
| GO | 2.020 | R$ 347.707 |
| ES | 2.033 | R$ 324.802 |

> SP domina (~42% do volume). Região Sul/SE concentra ~80% da receita.

---

## Cobertura IBGE

### Municípios por macrorregião
| Macrorregião | Municípios |
|---|---|
| Nordeste | 1.794 |
| Sudeste | 1.668 |
| Sul | 1.191 |
| Centro-Oeste | 468 |
| Norte | 450 |
| **Total** | **5.571** |

### Cobertura de covariáveis (int_ibge_censo_covariaveis)
| Total | Populacao | Renda média | Renda mediana | % Internet |
|---|---|---|---|---|
| 5.570 | 5.570 | 5.570 | 5.570 | 5.570 |

> Cobertura total: sem nulos nas covariáveis. 1 município ausente = Fernando de Noronha (já documentado em `specs/dbt/intermediate_ibge.md`).

### Join municipios + covariaveis
| Total municípios | Com covariáveis | Cobertura |
|---|---|---|
| 5.571 | 5.570 | **99,98%** |

---

## Cobertura BCB PIX

### Temporal
| Primeiro mês | Último mês | Meses | Municípios |
|---|---|---|---|
| 2020-11 | 2026-06 | 68 | 5.571 |

> PIX cobre todos os 5.571 municípios IBGE — **100% de overlap** com `int_ibge_municipios`. Não há gap de FK.

### Médias por município-mês
| Métrica | Valor |
|---|---|
| Transações pagador (média) | ~597k |
| Transações recebedor (média) | ~597k |
| Valor pagador (média) | R$ 250M |
| Valor recebedor (média) | R$ 250M |

> Valores médios altos são esperados: soma de todas as transações PIX do município no mês, não por pessoa.

---

## Decisões para o mart

### Estrutura: três modelos

| Modelo | Grain | Fonte |
|---|---|---|
| `mart_olist` | (id_municipio, ano) | int_fact_orders + int_dim_customers + int_dim_sellers + int_ibge_municipios |
| `mart_ibge_pix` | (id_municipio, ano) | int_ibge_municipios + int_bcb_pix_municipio |
| `mart_geo_analytics` | (id_municipio) | mart_olist × mart_ibge_pix |

**Limitação declarada:** Olist cobre 2017–2018; PIX cobre 2020–2026; censo IBGE é 2022. O join final em `mart_geo_analytics` é cross-período — não há alinhamento temporal entre as fontes.

### Decisões de design

1. **Sem filtro por `order_status` no mart_olist** — construir métricas separadas por status para permitir análise de cancelamentos, processamento etc. Corte temporal: `order_purchase_timestamp >= '2017-01-01'` (remove os 329 pedidos de 2016, cobertura parcial).

2. **Join final reflete municípios Olist** — `mart_geo_analytics` usa `mart_olist` como lado esquerdo (INNER com `mart_ibge_pix`): apenas os 2.361 municípios com pelo menos um pedido Olist compõem o mart final.

3. **Município do customer como chave geográfica** — rota:
   ```
   int_fact_orders.customer_zip_code_prefix
     → int_olist_geolocation.geolocation_city_slug
       → int_ibge_municipios.nome_municipio_slug + uf_sigla
   ```
   Cobertura: **99,2% dos pedidos**, 4.009 municípios distintos. Slug gerado por `normalize_city_name()` (macro dbt): remove acentos, snake_case.

4. **int_dim_sellers contribui com `vendedores_no_municipio`** — contagem de sellers com sede naquele município via `seller_city_slug = nome_municipio_slug AND seller_state = uf_sigla`. Não há FK direta seller → order no intermediate; `unique_sellers_count` do fact captura sellers por pedido, não por município.

5. **Covariáveis de `int_ibge_municipios` diretamente** — sem JOIN adicional com `int_ibge_censo_covariaveis`.

6. **Colunas reais (corrigidas vs. spec anterior):**
   - `items_count` (não `total_items`)
   - `review_score IS NOT NULL` para presença de review (não há coluna `has_review` booleana)

7. **Chaves de join `_slug` implementadas no intermediate:**
   - `int_ibge_municipios.nome_municipio_slug` — PK composta com `uf_sigla`
   - `int_olist_geolocation.geolocation_city_slug`
   - `int_dim_sellers.seller_city_slug`
   - `int_dim_customers.customer_city_slug`

---

## Métricas sugeridas

### mart_olist — (id_municipio, ano)

**Volume e status**
| Métrica | Definição |
|---|---|
| `total_pedidos` | COUNT(*) |
| `pedidos_entregues` | COUNT WHERE order_status = 'delivered' |
| `pedidos_cancelados` | COUNT WHERE order_status IN ('canceled', 'unavailable') |
| `pedidos_em_andamento` | COUNT WHERE order_status IN ('shipped', 'invoiced', 'processing', 'approved', 'created') |
| `taxa_entrega` | pedidos_entregues / total_pedidos |
| `taxa_cancelamento` | pedidos_cancelados / total_pedidos |
| `clientes_unicos` | COUNT DISTINCT customer_unique_id |
| `vendedores_no_municipio` | COUNT sellers com sede no município (int_dim_sellers) |

**Financeiro** (pedidos entregues)
| Métrica | Definição |
|---|---|
| `receita_total` | SUM total_revenue |
| `ticket_medio` | AVG total_revenue |
| `frete_medio` | AVG total_freight_value |
| `share_frete` | frete_medio / ticket_medio |
| `avg_parcelas_cartao` | AVG credit_card_installments WHERE credit_card_value > 0 |
| `pct_pagamento_cartao` | SUM credit_card_value / SUM total_payment_value |
| `pct_pagamento_boleto` | SUM boleto_value / SUM total_payment_value |

**Logística** (pedidos entregues)
| Métrica | Definição |
|---|---|
| `avg_dias_entrega` | AVG delivery_days |
| `avg_dias_aprovacao` | AVG approval_days |
| `taxa_entrega_no_prazo` | COUNT WHERE is_on_time / pedidos_entregues |

**Satisfação** (pedidos com review_score não nulo)
| Métrica | Definição |
|---|---|
| `avg_review_score` | AVG review_score |
| `pct_avaliacao_positiva` | COUNT WHERE review_score >= 4 / pedidos com review |
| `pct_avaliacao_negativa` | COUNT WHERE review_score <= 2 / pedidos com review |
| `pct_pedidos_com_review` | COUNT WHERE review_score IS NOT NULL / pedidos_entregues |

---

### mart_ibge_pix — (id_municipio, ano)

**IBGE** (covariáveis estáticas — repetidas em todos os anos)
| Métrica | Definição |
|---|---|
| `populacao_residente` | da int_ibge_municipios (censo 2022) |
| `renda_media_per_capita` | idem |
| `renda_mediana_per_capita` | idem |
| `pct_domicilios_com_internet` | idem |
| `macroregiao_nome` / `uf_sigla` | idem |

**PIX** (agregação mensal → anual)
| Métrica | Definição |
|---|---|
| `total_transacoes_pix` | SUM qt_total_transacoes_pagador |
| `total_valor_pix` | SUM vl_total_pagador |
| `valor_pix_per_capita` | total_valor_pix / populacao_residente |
| `transacoes_pix_per_capita` | total_transacoes_pix / populacao_residente |
| `pct_transacoes_pf` | SUM qt_pagador_pf / SUM qt_total_transacoes_pagador |
| `pct_valor_pj` | SUM vl_pagador_pj / SUM vl_total_pagador |
| `n_meses_pix` | COUNT DISTINCT ano_mes_data (completude do ano) |

---

### mart_geo_analytics — (id_municipio)

Join INNER de `mart_olist` (agregado total do período) com `mart_ibge_pix` (agregado total do período), restrito aos municípios Olist.

Herda todas as métricas dos dois marts acima. Métricas adicionais derivadas do cruzamento:

| Métrica | Definição |
|---|---|
| `receita_por_habitante` | receita_total / populacao_residente |
| `pedidos_por_habitante` | total_pedidos / populacao_residente |
| `penetracao_olist` | clientes_unicos / populacao_residente |
