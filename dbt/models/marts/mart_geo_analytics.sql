with olist_2018 as (
    select *
    from {{ ref('mart_olist') }}
    where ano = 2018
),

pix_periodo as (
    select
        id_municipio,
        max(nome_municipio)                                                                     as nome_municipio,
        max(uf_sigla)                                                                           as uf_sigla,
        max(macroregiao_nome)                                                                   as macroregiao_nome,
        max(populacao_residente)                                                                as populacao_residente,
        max(renda_media_per_capita)                                                             as renda_media_per_capita,
        max(renda_mediana_per_capita)                                                           as renda_mediana_per_capita,
        max(pct_domicilios_com_internet)                                                        as pct_domicilios_com_internet,
        sum(total_transacoes_pagador)                                                           as total_transacoes_pagador,
        sum(total_valor_pagador)                                                                as total_valor_pagador,
        sum(total_transacoes_recebedor)                                                         as total_transacoes_recebedor,
        sum(total_valor_recebedor)                                                              as total_valor_recebedor,
        sum(qt_pagador_pf)                                                                      as qt_pagador_pf,
        sum(vl_recebedor_pj)                                                                    as vl_recebedor_pj,
        sum(qt_recebedor_pj)                                                                    as qt_recebedor_pj,
        count(distinct ano)                                                                     as anos_pix_disponiveis
    from {{ ref('mart_ibge_pix') }}
    group by id_municipio
),

final as (
    select
        -- dimensões (fonte autoritativa: mart_ibge_pix)
        p.id_municipio,
        p.nome_municipio,
        p.uf_sigla,
        p.macroregiao_nome,

        -- olist 2018
        o.total_pedidos,
        o.pedidos_entregues,
        o.pedidos_cancelados,
        o.pedidos_em_andamento,
        o.taxa_entrega,
        o.taxa_cancelamento,
        o.clientes_unicos,
        o.vendedores_no_municipio,
        o.receita_total,
        o.ticket_medio,
        o.frete_medio,
        o.share_frete,
        COALESCE(o.pct_pagamento_cartao, 0.0)                                                    AS pct_pagamento_cartao,
        o.pct_pagamento_boleto,
        o.avg_parcelas_cartao,
        o.avg_dias_entrega,
        o.avg_dias_aprovacao,
        o.taxa_entrega_no_prazo,
        o.avg_review_score,
        o.pct_avaliacao_positiva,
        o.pct_avaliacao_negativa,
        o.pct_pedidos_com_review,

        -- ibge censo 2022
        p.populacao_residente,
        p.renda_media_per_capita,
        p.renda_mediana_per_capita,
        p.pct_domicilios_com_internet,

        -- pix período total (re-agregado)
        p.total_transacoes_pagador,
        p.total_valor_pagador,
        p.total_valor_recebedor,
        p.total_valor_pagador / nullif(p.populacao_residente, 0)                                as valor_pix_per_capita,
        CAST(p.total_transacoes_pagador AS FLOAT64) / nullif(p.populacao_residente, 0)           as transacoes_pix_per_capita,
        CAST(p.qt_pagador_pf AS FLOAT64) / nullif(p.total_transacoes_pagador, 0)                as pct_transacoes_pagador_pf,
        p.vl_recebedor_pj / nullif(p.total_valor_recebedor, 0)                                 as pct_valor_recebedor_pj,
        CAST(p.qt_recebedor_pj AS FLOAT64) / nullif(p.total_transacoes_recebedor, 0)            as pct_transacoes_recebedor_pj,
        p.anos_pix_disponiveis,

        -- derivadas cruzadas
        o.receita_total / nullif(p.populacao_residente, 0)                                     as receita_por_habitante,
        CAST(o.total_pedidos AS FLOAT64) / nullif(p.populacao_residente, 0)                     as pedidos_por_habitante,
        CAST(o.clientes_unicos AS FLOAT64) / nullif(p.populacao_residente, 0)                     as penetracao_olist,

        -- categorias para filtros
        CASE
            WHEN p.populacao_residente < 10000  THEN 'Micro (< 10 mil)'
            WHEN p.populacao_residente < 50000  THEN 'Pequeno (10–50 mil)'
            WHEN p.populacao_residente < 200000 THEN 'Médio (50–200 mil)'
            ELSE                                     'Grande (≥ 200 mil)'
        END                                                                                      AS categoria_populacao,
        CASE
            WHEN CAST(o.clientes_unicos AS FLOAT64) / NULLIF(p.populacao_residente, 0) IS NULL  THEN 'Sem presença'
            WHEN CAST(o.clientes_unicos AS FLOAT64) / NULLIF(p.populacao_residente, 0) < 0.0001 THEN 'Baixa'
            WHEN CAST(o.clientes_unicos AS FLOAT64) / NULLIF(p.populacao_residente, 0) < 0.0003 THEN 'Média'
            ELSE                                                                                      'Alta'
        END                                                                                      AS categoria_olist

    from olist_2018 o
    inner join pix_periodo p on o.id_municipio = p.id_municipio
)

select * from final
