with orders_municipio as (
    select
        o.order_id,
        o.customer_unique_id,
        o.order_status,
        o.order_purchase_timestamp,
        extract(year from o.order_purchase_timestamp)   as ano,
        o.total_revenue,
        o.total_freight_value,
        o.total_payment_value,
        o.credit_card_value,
        o.credit_card_installments,
        o.boleto_value,
        o.delivery_days,
        o.approval_days,
        o.is_on_time,
        o.review_score,
        m.id_municipio,
        m.nome_municipio,
        m.uf_sigla,
        m.macroregiao_nome
    from {{ ref('int_fact_orders') }} o
    inner join {{ ref('int_olist_geolocation') }} g
        on o.customer_zip_code_prefix = g.geolocation_zip_code_prefix
    inner join {{ ref('int_ibge_municipios') }} m
        on g.geolocation_city_slug = m.nome_municipio_slug
        and upper(g.geolocation_state) = m.uf_sigla
    where o.order_purchase_timestamp >= '2017-01-01'
),

sellers_municipio as (
    select
        m.id_municipio,
        count(s.seller_id)  as vendedores_no_municipio
    from {{ ref('int_dim_sellers') }} s
    inner join {{ ref('int_ibge_municipios') }} m
        on s.seller_city_slug = m.nome_municipio_slug
        and upper(s.seller_state) = m.uf_sigla
    group by m.id_municipio
),

aggregated as (
    select
        id_municipio,
        nome_municipio,
        uf_sigla,
        macroregiao_nome,
        ano,

        -- volume
        count(*)                                                                                                            as total_pedidos,
        sum(case when order_status = 'delivered' then 1 else 0 end)                                                        as pedidos_entregues,
        sum(case when order_status in ('canceled', 'unavailable') then 1 else 0 end)                                       as pedidos_cancelados,
        sum(case when order_status in ('shipped', 'invoiced', 'processing', 'approved', 'created') then 1 else 0 end)      as pedidos_em_andamento,
        CAST(sum(case when order_status = 'delivered' then 1 else 0 end) AS FLOAT64)
            / nullif(count(*), 0)                                                                                           as taxa_entrega,
        CAST(sum(case when order_status in ('canceled', 'unavailable') then 1 else 0 end) AS FLOAT64)
            / nullif(count(*), 0)                                                                                           as taxa_cancelamento,
        count(distinct customer_unique_id)                                                                                  as clientes_unicos,

        -- financeiro (apenas pedidos entregues)
        sum(case when order_status = 'delivered' then total_revenue else 0 end)                                             as receita_total,
        avg(case when order_status = 'delivered' then total_revenue end)                                                    as ticket_medio,
        avg(case when order_status = 'delivered' then total_freight_value end)                                              as frete_medio,
        sum(case when order_status = 'delivered' then total_freight_value else 0 end)
            / nullif(sum(case when order_status = 'delivered' then total_revenue else 0 end), 0)                           as share_frete,
        sum(case when order_status = 'delivered' then credit_card_value else 0 end)
            / nullif(sum(case when order_status = 'delivered' then total_payment_value else 0 end), 0)                     as pct_pagamento_cartao,
        sum(case when order_status = 'delivered' then boleto_value else 0 end)
            / nullif(sum(case when order_status = 'delivered' then total_payment_value else 0 end), 0)                     as pct_pagamento_boleto,
        avg(case when order_status = 'delivered' and credit_card_value > 0 then credit_card_installments end)              as avg_parcelas_cartao,

        -- logística (apenas pedidos entregues)
        avg(case when order_status = 'delivered' then delivery_days end)                                                    as avg_dias_entrega,
        avg(case when order_status = 'delivered' then approval_days end)                                                    as avg_dias_aprovacao,
        CAST(sum(case when is_on_time = true then 1 else 0 end) AS FLOAT64)
            / nullif(sum(case when order_status = 'delivered' then 1 else 0 end), 0)                                       as taxa_entrega_no_prazo,

        -- satisfação (pedidos com review)
        avg(review_score)                                                                                                   as avg_review_score,
        CAST(sum(case when review_score >= 4 then 1 else 0 end) AS FLOAT64)
            / nullif(sum(case when review_score is not null then 1 else 0 end), 0)                                         as pct_avaliacao_positiva,
        CAST(sum(case when review_score <= 2 then 1 else 0 end) AS FLOAT64)
            / nullif(sum(case when review_score is not null then 1 else 0 end), 0)                                         as pct_avaliacao_negativa,
        CAST(sum(case when review_score is not null then 1 else 0 end) AS FLOAT64)
            / nullif(sum(case when order_status = 'delivered' then 1 else 0 end), 0)                                       as pct_pedidos_com_review

    from orders_municipio
    group by id_municipio, nome_municipio, uf_sigla, macroregiao_nome, ano
),

final as (
    select
        a.id_municipio,
        a.nome_municipio,
        a.uf_sigla,
        a.macroregiao_nome,
        a.ano,
        a.total_pedidos,
        a.pedidos_entregues,
        a.pedidos_cancelados,
        a.pedidos_em_andamento,
        a.taxa_entrega,
        a.taxa_cancelamento,
        a.clientes_unicos,
        s.vendedores_no_municipio,
        a.receita_total,
        a.ticket_medio,
        a.frete_medio,
        a.share_frete,
        a.pct_pagamento_cartao,
        a.pct_pagamento_boleto,
        a.avg_parcelas_cartao,
        a.avg_dias_entrega,
        a.avg_dias_aprovacao,
        a.taxa_entrega_no_prazo,
        a.avg_review_score,
        a.pct_avaliacao_positiva,
        a.pct_avaliacao_negativa,
        a.pct_pedidos_com_review
    from aggregated a
    left join sellers_municipio s on a.id_municipio = s.id_municipio
)

select * from final
