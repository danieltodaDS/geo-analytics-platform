with pix_anual as (
    select
        municipio_ibge,
        extract(year from ano_mes_data)             as ano,
        count(distinct ano_mes_data)                as n_meses_pix,
        sum(qt_total_transacoes_pagador)            as total_transacoes_pagador,
        sum(vl_total_pagador)                       as total_valor_pagador,
        sum(qt_pagador_pf)                          as qt_pagador_pf,
        sum(qt_total_transacoes_recebedor)          as total_transacoes_recebedor,
        sum(vl_total_recebedor)                     as total_valor_recebedor,
        sum(vl_recebedor_pj)                        as vl_recebedor_pj,
        sum(qt_recebedor_pj)                        as qt_recebedor_pj
    from {{ ref('int_bcb_pix_municipio') }}
    group by municipio_ibge, extract(year from ano_mes_data)
),

final as (
    select
        m.id_municipio,
        m.nome_municipio,
        m.uf_sigla,
        m.macroregiao_nome,
        p.ano,

        -- ibge censo 2022 (covariáveis estáticas)
        m.populacao_residente,
        m.renda_media_per_capita,
        m.renda_mediana_per_capita,
        m.pct_domicilios_com_internet,

        -- pix pagador
        p.total_transacoes_pagador,
        p.total_valor_pagador,
        p.qt_pagador_pf,
        p.total_valor_pagador / nullif(m.populacao_residente, 0)                    as valor_pix_per_capita,
        CAST(p.total_transacoes_pagador AS FLOAT64) / nullif(m.populacao_residente, 0) as transacoes_pix_per_capita,
        CAST(p.qt_pagador_pf AS FLOAT64) / nullif(p.total_transacoes_pagador, 0)     as pct_transacoes_pagador_pf,

        -- pix recebedor
        p.total_transacoes_recebedor,
        p.total_valor_recebedor,
        p.vl_recebedor_pj,
        p.qt_recebedor_pj,
        p.vl_recebedor_pj / nullif(p.total_valor_recebedor, 0)                     as pct_valor_recebedor_pj,
        CAST(p.qt_recebedor_pj AS FLOAT64) / nullif(p.total_transacoes_recebedor, 0) as pct_transacoes_recebedor_pj,
        p.n_meses_pix

    from {{ ref('int_ibge_municipios') }} m
    inner join pix_anual p on m.id_municipio = p.municipio_ibge
)

select * from final
