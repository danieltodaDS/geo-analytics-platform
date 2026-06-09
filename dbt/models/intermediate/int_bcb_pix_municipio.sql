with source as (
    select * from {{ ref('stg_bcb_pix') }}
)

select
    municipio_ibge,
    strptime(ano_mes::varchar, '%Y%m')::date     as ano_mes_data,
    municipio,
    estado_ibge,
    estado,
    sigla_regiao,
    regiao,

    -- perspectiva pagador (saída do município)
    vl_pagador_pf,
    qt_pagador_pf,
    vl_pagador_pj,
    qt_pagador_pj,
    vl_pagador_pf + vl_pagador_pj               as vl_total_pagador,
    qt_pagador_pf + qt_pagador_pj               as qt_total_transacoes_pagador,
    qt_pes_pagador_pf,
    qt_pes_pagador_pj,

    -- perspectiva recebedor (entrada no município)
    vl_recebedor_pf,
    qt_recebedor_pf,
    vl_recebedor_pj,
    qt_recebedor_pj,
    vl_recebedor_pf + vl_recebedor_pj           as vl_total_recebedor,
    qt_recebedor_pf + qt_recebedor_pj           as qt_total_transacoes_recebedor,
    qt_pes_recebedor_pf,
    qt_pes_recebedor_pj

from source
