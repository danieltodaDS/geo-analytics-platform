# Spec — dbt Marts (Feature 6)

> Pré-requisito: camada intermediate fechada e testada (int_fact_orders, int_dim_customers, int_dim_sellers, int_olist_geolocation, int_ibge_municipios, int_bcb_pix_municipio).
> Fase coberta: **4a — Local A** (dbt-duckdb).
> Antes de gerar código, leia esta spec na íntegra.
> Understanding: `docs/understanding/mart_geo_analytics.md`.

---

## Contrato da camada

```
O que chega:    Modelos intermediate (joins, dedup semântica e regras de negócio já aplicados)
O que muda:     Agregações finais, métricas derivadas, exposição ao consumidor
O que NÃO muda: Granularidade não aumenta — cada mart reduz ou mantém o grão do intermediate
Regras:         Prontos para consumo — sem joins adicionais necessários pelo consumidor
Documentação:   description obrigatório em toda coluna exposta (normativo data_quality.md)
```

---

## Estrutura e dependências

```
mart_olist            (id_municipio, ano)
├── int_fact_orders
├── int_olist_geolocation
├── int_ibge_municipios
└── int_dim_sellers

mart_ibge_pix         (id_municipio, ano)
├── int_ibge_municipios
└── int_bcb_pix_municipio

mart_geo_analytics    (id_municipio)
├── mart_olist          — filtrado para ano = 2018 (último ano completo Olist)
└── mart_ibge_pix       — agregado sobre todo o período PIX disponível
```

**Limitação declarada:** Olist cobre 2017–2018; PIX cobre 2020–2026; censo IBGE é 2022. `mart_geo_analytics` é cross-período — não há alinhamento temporal entre as fontes.

---

## Chave de geocodificação

O join `int_fact_orders` → `int_ibge_municipios` passa obrigatoriamente por `int_olist_geolocation`:

```
int_fact_orders.customer_zip_code_prefix
  = int_olist_geolocation.geolocation_zip_code_prefix
    → int_olist_geolocation.geolocation_city_slug
      = int_ibge_municipios.nome_municipio_slug
        AND upper(int_olist_geolocation.geolocation_state) = int_ibge_municipios.uf_sigla
```

Cobertura medida: **99,2% dos pedidos** (2017+). Pedidos sem `id_municipio` após o join são descartados via `WHERE m.id_municipio IS NOT NULL`. Idem para sellers em `mart_olist`.

---

## Modelos

### mart_olist

**Responsabilidade:** métricas de e-commerce Olist agregadas por município do comprador e ano.

**Grain:** 1 linha por `(id_municipio, ano)`.

**Fontes:**
- `int_fact_orders` — pedidos com métricas pré-calculadas
- `int_olist_geolocation` — ponte ZIP → (city_slug, state)
- `int_ibge_municipios` — resolução do id_municipio via slug
- `int_dim_sellers` — contagem de sellers com sede no município

**Filtro:** `order_purchase_timestamp >= '2017-01-01'`. Sem filtro por `order_status` — todos os status são preservados; métricas são calculadas por subset de status conforme definição abaixo.

#### Estrutura de CTEs

```
orders_municipio      → int_fact_orders + geo join → adiciona id_municipio e ano; descarta sem município
sellers_municipio     → int_dim_sellers + int_ibge_municipios → COUNT sellers por id_municipio
                         (sem dimensão temporal — dataset Olist é estático; mesmo valor para 2017 e 2018)
aggregated            → GROUP BY id_municipio, nome_municipio, uf_sigla, macroregiao_nome, ano
final                 → aggregated LEFT JOIN sellers_municipio ON id_municipio
```

#### Colunas

**Dimensões**

| Coluna | Tipo | Definição |
|---|---|---|
| `id_municipio` | BIGINT | Código IBGE (7 dígitos). PK composta com `ano`. |
| `nome_municipio` | VARCHAR | Nome oficial IBGE. |
| `uf_sigla` | VARCHAR | Sigla da UF. |
| `macroregiao_nome` | VARCHAR | Nome da macrorregião (Norte, Nordeste, etc.). |
| `ano` | INTEGER | `EXTRACT(year FROM order_purchase_timestamp)`. |

**Volume**

| Coluna | Tipo | Definição |
|---|---|---|
| `total_pedidos` | BIGINT | `COUNT(*)` — todos os status. |
| `pedidos_entregues` | BIGINT | `SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END)` |
| `pedidos_cancelados` | BIGINT | `SUM(CASE WHEN order_status IN ('canceled', 'unavailable') THEN 1 ELSE 0 END)` |
| `pedidos_em_andamento` | BIGINT | `SUM(CASE WHEN order_status IN ('shipped', 'invoiced', 'processing', 'approved', 'created') THEN 1 ELSE 0 END)` |
| `taxa_entrega` | DOUBLE | `SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)` |
| `taxa_cancelamento` | DOUBLE | `SUM(CASE WHEN order_status IN ('canceled', 'unavailable') THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)` |
| `clientes_unicos` | BIGINT | `COUNT(DISTINCT customer_unique_id)` — todos os status. |
| `vendedores_no_municipio` | BIGINT | Sellers com sede no município. NULL se nenhum. Via `int_dim_sellers.seller_city_slug`. Atemporal — o resultado é idêntico para todos os anos, dado que o dataset Olist é estático. |

**Financeiro** (apenas pedidos entregues — condição `order_status = 'delivered'` embutida em cada expressão)

| Coluna | Tipo | Definição |
|---|---|---|
| `receita_total` | DOUBLE | `SUM(CASE WHEN order_status = 'delivered' THEN total_revenue ELSE 0 END)` |
| `ticket_medio` | DOUBLE | `AVG(CASE WHEN order_status = 'delivered' THEN total_revenue END)` |
| `frete_medio` | DOUBLE | `AVG(CASE WHEN order_status = 'delivered' THEN total_freight_value END)` |
| `share_frete` | DOUBLE | `SUM(CASE WHEN order_status = 'delivered' THEN total_freight_value ELSE 0 END) / NULLIF(SUM(CASE WHEN order_status = 'delivered' THEN total_revenue ELSE 0 END), 0)` |
| `pct_pagamento_cartao` | DOUBLE | `SUM(CASE WHEN order_status = 'delivered' THEN credit_card_value ELSE 0 END) / NULLIF(SUM(CASE WHEN order_status = 'delivered' THEN total_payment_value ELSE 0 END), 0)` |
| `pct_pagamento_boleto` | DOUBLE | `SUM(CASE WHEN order_status = 'delivered' THEN boleto_value ELSE 0 END) / NULLIF(SUM(CASE WHEN order_status = 'delivered' THEN total_payment_value ELSE 0 END), 0)` |
| `avg_parcelas_cartao` | DOUBLE | `AVG(CASE WHEN order_status = 'delivered' AND credit_card_value > 0 THEN credit_card_installments END)` |

**Logística** (apenas pedidos entregues)

| Coluna | Tipo | Definição |
|---|---|---|
| `avg_dias_entrega` | DOUBLE | `AVG(CASE WHEN order_status = 'delivered' THEN delivery_days END)` |
| `avg_dias_aprovacao` | DOUBLE | `AVG(CASE WHEN order_status = 'delivered' THEN approval_days END)` |
| `taxa_entrega_no_prazo` | DOUBLE | `SUM(CASE WHEN is_on_time = true THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END), 0)` |

**Satisfação** (pedidos com `review_score IS NOT NULL`)

| Coluna | Tipo | Definição |
|---|---|---|
| `avg_review_score` | DOUBLE | `AVG(review_score)` — NULL excluído nativamente pelo AVG. |
| `pct_avaliacao_positiva` | DOUBLE | `SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END), 0)` |
| `pct_avaliacao_negativa` | DOUBLE | `SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END), 0)` |
| `pct_pedidos_com_review` | DOUBLE | `SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END), 0)` |

#### Testes

| Teste | Condição |
|---|---|
| `unique_combination_of_columns` | `[id_municipio, ano]` |
| `not_null` | `id_municipio, nome_municipio, uf_sigla, macroregiao_nome, ano` |
| `relationships` | `id_municipio → int_ibge_municipios.id_municipio` |
| `expression_is_true` | `total_pedidos > 0` |
| `expression_is_true` | `pedidos_entregues >= 0 AND pedidos_entregues <= total_pedidos` |
| `expression_is_true` | `taxa_entrega IS NULL OR (taxa_entrega >= 0 AND taxa_entrega <= 1)` |
| `expression_is_true` | `taxa_cancelamento IS NULL OR (taxa_cancelamento >= 0 AND taxa_cancelamento <= 1)` |
| `expression_is_true` | `receita_total IS NULL OR receita_total >= 0` |
| `expression_is_true` | `ticket_medio IS NULL OR ticket_medio >= 0` |
| `expression_is_true` | `avg_dias_entrega IS NULL OR avg_dias_entrega >= 0` |
| `expression_is_true` | `avg_review_score IS NULL OR (avg_review_score >= 1 AND avg_review_score <= 5)` |

---

### mart_ibge_pix

**Responsabilidade:** covariáveis municipais IBGE (estáticas) combinadas com métricas PIX anuais — separadas em pagador (adesão ao serviço) e recebedor (digitalização do comércio local).

**Grain:** 1 linha por `(id_municipio, ano)`. Anos parciais (ex: 2026 com menos de 12 meses) são incluídos; `n_meses_pix` sinaliza completude.

**Fontes:**
- `int_ibge_municipios` — geografias e covariáveis estáticas do Censo 2022
- `int_bcb_pix_municipio` — transações PIX por município/mês

#### Estrutura de CTEs

```
pix_anual    → int_bcb_pix_municipio GROUP BY municipio_ibge, EXTRACT(year FROM ano_mes_data)
final        → int_ibge_municipios INNER JOIN pix_anual ON id_municipio = municipio_ibge
```

INNER JOIN correto: PIX tem cobertura de 100% dos 5.571 municípios IBGE (verificado na exploração). Nenhum município IBGE fica de fora.

#### Colunas

**Dimensões**

| Coluna | Tipo | Definição |
|---|---|---|
| `id_municipio` | BIGINT | Código IBGE. PK composta com `ano`. |
| `nome_municipio` | VARCHAR | Nome oficial IBGE. |
| `uf_sigla` | VARCHAR | Sigla da UF. |
| `macroregiao_nome` | VARCHAR | Nome da macrorregião. |
| `ano` | INTEGER | `EXTRACT(year FROM ano_mes_data)` do PIX. |

**IBGE** (Censo 2022 — mesmo valor em todos os anos)

| Coluna | Tipo | Definição |
|---|---|---|
| `populacao_residente` | DOUBLE | Fonte: `int_ibge_municipios`. |
| `renda_media_per_capita` | DOUBLE | Rendimento médio mensal domiciliar per capita (R$). |
| `renda_mediana_per_capita` | DOUBLE | Rendimento mediano mensal domiciliar per capita (R$). |
| `pct_domicilios_com_internet` | DOUBLE | % domicílios com internet. |

**PIX — Pagador** (validar adesão ao serviço)

| Coluna | Tipo | Definição |
|---|---|---|
| `total_transacoes_pagador` | BIGINT | `SUM(qt_total_transacoes_pagador)` no ano. |
| `total_valor_pagador` | DOUBLE | `SUM(vl_total_pagador)` no ano (R$). |
| `qt_pagador_pf` | BIGINT | `SUM(qt_pagador_pf)` — exposto como raw para re-agregação em `mart_geo_analytics`. |
| `valor_pix_per_capita` | DOUBLE | `SUM(vl_total_pagador) / NULLIF(populacao_residente, 0)` |
| `transacoes_pix_per_capita` | DOUBLE | `SUM(qt_total_transacoes_pagador) / NULLIF(populacao_residente, 0)` |
| `pct_transacoes_pagador_pf` | DOUBLE | `SUM(qt_pagador_pf) / NULLIF(SUM(qt_total_transacoes_pagador), 0)` |

**PIX — Recebedor** (avaliar digitalização do comércio)

| Coluna | Tipo | Definição |
|---|---|---|
| `total_transacoes_recebedor` | BIGINT | `SUM(qt_total_transacoes_recebedor)` no ano. |
| `total_valor_recebedor` | DOUBLE | `SUM(vl_total_recebedor)` no ano (R$). |
| `vl_recebedor_pj` | DOUBLE | `SUM(vl_recebedor_pj)` — exposto como raw para re-agregação. |
| `qt_recebedor_pj` | BIGINT | `SUM(qt_recebedor_pj)` — exposto como raw para re-agregação. |
| `pct_valor_recebedor_pj` | DOUBLE | `SUM(vl_recebedor_pj) / NULLIF(SUM(vl_total_recebedor), 0)` |
| `pct_transacoes_recebedor_pj` | DOUBLE | `SUM(qt_recebedor_pj) / NULLIF(SUM(qt_total_transacoes_recebedor), 0)` |
| `n_meses_pix` | INTEGER | `COUNT(DISTINCT ano_mes_data)` — completude do ano; máx 12. |

#### Testes

| Teste | Condição |
|---|---|
| `unique_combination_of_columns` | `[id_municipio, ano]` |
| `not_null` | `id_municipio, nome_municipio, uf_sigla, ano` |
| `relationships` | `id_municipio → int_ibge_municipios.id_municipio` |
| `expression_is_true` | `total_transacoes_pagador >= 0` |
| `expression_is_true` | `total_valor_pagador >= 0` |
| `expression_is_true` | `total_valor_recebedor >= 0` |
| `expression_is_true` | `pct_transacoes_pagador_pf IS NULL OR (pct_transacoes_pagador_pf >= 0 AND pct_transacoes_pagador_pf <= 1)` |
| `expression_is_true` | `pct_valor_recebedor_pj IS NULL OR (pct_valor_recebedor_pj >= 0 AND pct_valor_recebedor_pj <= 1)` |
| `expression_is_true` | `n_meses_pix >= 1 AND n_meses_pix <= 12` |

---

### mart_geo_analytics

**Responsabilidade:** mart final para análise cross-domínio — Olist (2018) × IBGE × PIX (período total). Join restrito aos municípios com presença Olist.

**Grain:** 1 linha por `id_municipio`.

**Fontes:**
- `mart_olist` filtrado para `ano = 2018`
- `mart_ibge_pix` agregado sobre todo o período PIX disponível

**Tipo de join:** `mart_olist (ano=2018)` INNER JOIN `mart_ibge_pix (agregado)` ON `id_municipio`. Como PIX cobre 100% dos municípios IBGE e todos os municípios Olist estão no IBGE, o INNER JOIN retorna exatamente os municípios Olist — sem perda.

**Fonte autoritativa para dimensões:** todas as colunas dimensionais (`nome_municipio`, `uf_sigla`, `macroregiao_nome`) vêm de `mart_ibge_pix` (lado IBGE). As colunas com mesmo nome em `mart_olist` são descartadas no SELECT final.

**Limitação declarada no catálogo:** as fontes não são contemporâneas. Olist = 2018; censo IBGE = 2022; PIX = 2020–2026. Comparações causais diretas entre fontes requerem controle de período.

#### Estrutura de CTEs

```
olist_2018     → mart_olist WHERE ano = 2018
pix_periodo    → mart_ibge_pix GROUP BY id_municipio
                  totais: SUM(); covariáveis IBGE estáticas: MAX(); taxas: re-derivadas de raw counts
final          → olist_2018 INNER JOIN pix_periodo ON id_municipio
```

Covariáveis IBGE em `pix_periodo`: `MAX(populacao_residente)`, `MAX(renda_media_per_capita)`, `MAX(renda_mediana_per_capita)`, `MAX(pct_domicilios_com_internet)`. O valor é idêntico em todos os anos — MAX é semanticamente equivalente a qualquer outra função de agregação; usado por convenção.

#### Colunas

**Dimensões** (fonte: `mart_ibge_pix`)

| Coluna | Tipo | Definição |
|---|---|---|
| `id_municipio` | BIGINT | PK. |
| `nome_municipio` | VARCHAR | Nome oficial IBGE. |
| `uf_sigla` | VARCHAR | Sigla da UF. |
| `macroregiao_nome` | VARCHAR | Nome da macrorregião. |

**Olist 2018** (herdado de `mart_olist` para `ano = 2018`)

| Coluna | Tipo | Definição |
|---|---|---|
| `total_pedidos` | BIGINT | Herdado de `mart_olist.total_pedidos`. |
| `pedidos_entregues` | BIGINT | Herdado de `mart_olist.pedidos_entregues`. |
| `pedidos_cancelados` | BIGINT | Herdado de `mart_olist.pedidos_cancelados`. |
| `pedidos_em_andamento` | BIGINT | Herdado de `mart_olist.pedidos_em_andamento`. |
| `taxa_entrega` | DOUBLE | Herdado de `mart_olist.taxa_entrega`. |
| `taxa_cancelamento` | DOUBLE | Herdado de `mart_olist.taxa_cancelamento`. |
| `clientes_unicos` | BIGINT | Herdado de `mart_olist.clientes_unicos`. |
| `vendedores_no_municipio` | BIGINT | Herdado de `mart_olist.vendedores_no_municipio`. |
| `receita_total` | DOUBLE | Herdado de `mart_olist.receita_total`. |
| `ticket_medio` | DOUBLE | Herdado de `mart_olist.ticket_medio`. |
| `frete_medio` | DOUBLE | Herdado de `mart_olist.frete_medio`. |
| `share_frete` | DOUBLE | Herdado de `mart_olist.share_frete`. |
| `pct_pagamento_cartao` | DOUBLE | Herdado de `mart_olist.pct_pagamento_cartao`. |
| `pct_pagamento_boleto` | DOUBLE | Herdado de `mart_olist.pct_pagamento_boleto`. |
| `avg_parcelas_cartao` | DOUBLE | Herdado de `mart_olist.avg_parcelas_cartao`. |
| `avg_dias_entrega` | DOUBLE | Herdado de `mart_olist.avg_dias_entrega`. |
| `avg_dias_aprovacao` | DOUBLE | Herdado de `mart_olist.avg_dias_aprovacao`. |
| `taxa_entrega_no_prazo` | DOUBLE | Herdado de `mart_olist.taxa_entrega_no_prazo`. |
| `avg_review_score` | DOUBLE | Herdado de `mart_olist.avg_review_score`. |
| `pct_avaliacao_positiva` | DOUBLE | Herdado de `mart_olist.pct_avaliacao_positiva`. |
| `pct_avaliacao_negativa` | DOUBLE | Herdado de `mart_olist.pct_avaliacao_negativa`. |
| `pct_pedidos_com_review` | DOUBLE | Herdado de `mart_olist.pct_pedidos_com_review`. |

**IBGE** (Censo 2022 — de `pix_periodo`)

| Coluna | Tipo | Definição |
|---|---|---|
| `populacao_residente` | DOUBLE | `MAX(populacao_residente)` de `mart_ibge_pix`. |
| `renda_media_per_capita` | DOUBLE | `MAX(renda_media_per_capita)` de `mart_ibge_pix`. |
| `renda_mediana_per_capita` | DOUBLE | `MAX(renda_mediana_per_capita)` de `mart_ibge_pix`. |
| `pct_domicilios_com_internet` | DOUBLE | `MAX(pct_domicilios_com_internet)` de `mart_ibge_pix`. |

**PIX — período total** (re-agregado de `mart_ibge_pix`)

| Coluna | Tipo | Definição |
|---|---|---|
| `total_transacoes_pagador` | BIGINT | `SUM(total_transacoes_pagador)` sobre todos os anos. |
| `total_transacoes_recebedor` | BIGINT | `SUM(total_transacoes_recebedor)` sobre todos os anos. Exposto para permitir re-derivação de `pct_transacoes_recebedor_pj` pelo consumidor. |
| `total_valor_pagador` | DOUBLE | `SUM(total_valor_pagador)` sobre todos os anos (R$). |
| `total_valor_recebedor` | DOUBLE | `SUM(total_valor_recebedor)` sobre todos os anos (R$). |
| `valor_pix_per_capita` | DOUBLE | `SUM(total_valor_pagador) / NULLIF(MAX(populacao_residente), 0)` — re-derivado. |
| `transacoes_pix_per_capita` | DOUBLE | `SUM(total_transacoes_pagador) / NULLIF(MAX(populacao_residente), 0)` — re-derivado. |
| `pct_transacoes_pagador_pf` | DOUBLE | `SUM(qt_pagador_pf) / NULLIF(SUM(total_transacoes_pagador), 0)` — re-derivado de raw. |
| `pct_valor_recebedor_pj` | DOUBLE | `SUM(vl_recebedor_pj) / NULLIF(SUM(total_valor_recebedor), 0)` — re-derivado de raw. |
| `pct_transacoes_recebedor_pj` | DOUBLE | `SUM(qt_recebedor_pj) / NULLIF(SUM(total_transacoes_recebedor), 0)` — re-derivado de raw. |
| `anos_pix_disponiveis` | INTEGER | `COUNT(DISTINCT ano)` de `mart_ibge_pix` para o município. |

**Derivadas cruzadas**

| Coluna | Tipo | Definição |
|---|---|---|
| `receita_por_habitante` | DOUBLE | `receita_total / NULLIF(populacao_residente, 0)` |
| `pedidos_por_habitante` | DOUBLE | `total_pedidos / NULLIF(populacao_residente, 0)` |
| `penetracao_olist` | DOUBLE | `clientes_unicos / NULLIF(populacao_residente, 0)` |

#### Testes

| Teste | Condição |
|---|---|
| `not_null` | `id_municipio` |
| `unique` | `id_municipio` |
| `relationships` | `id_municipio → int_ibge_municipios.id_municipio` |
| `expression_is_true` | `total_pedidos > 0` |
| `expression_is_true` | `pedidos_entregues >= 0 AND pedidos_entregues <= total_pedidos` |
| `expression_is_true` | `taxa_entrega IS NULL OR (taxa_entrega >= 0 AND taxa_entrega <= 1)` |
| `expression_is_true` | `taxa_cancelamento IS NULL OR (taxa_cancelamento >= 0 AND taxa_cancelamento <= 1)` |
| `expression_is_true` | `receita_total IS NULL OR receita_total >= 0` |
| `expression_is_true` | `ticket_medio IS NULL OR ticket_medio >= 0` |
| `expression_is_true` | `avg_dias_entrega IS NULL OR avg_dias_entrega >= 0` |
| `expression_is_true` | `avg_review_score IS NULL OR (avg_review_score >= 1 AND avg_review_score <= 5)` |
| `expression_is_true` | `receita_total IS NULL OR receita_por_habitante >= 0` |
| `expression_is_true` | `penetracao_olist IS NULL OR (penetracao_olist >= 0 AND penetracao_olist <= 1)` |
| `expression_is_true` | `pct_transacoes_pagador_pf IS NULL OR (pct_transacoes_pagador_pf >= 0 AND pct_transacoes_pagador_pf <= 1)` |
| `expression_is_true` | `pct_valor_recebedor_pj IS NULL OR (pct_valor_recebedor_pj >= 0 AND pct_valor_recebedor_pj <= 1)` |

---

## O que esta spec não cobre

- Modelos `_marts.yml` para catálogo — gerado na produtização
- Materialização incremental — escopo fase 4b/4c
- Filtragem por macrorregião ou UF específica — responsabilidade do consumidor (Streamlit / DS)

---

*Spec fechada em: Junho/2026*
