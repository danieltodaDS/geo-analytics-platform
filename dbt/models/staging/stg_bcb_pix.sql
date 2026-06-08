with source as (
    select * from {{ ref('bcb_pix') }}
)

select
    Municipio_Ibge::varchar || '-' || AnoMes::varchar as pix_pk,
    AnoMes         as ano_mes,
    Municipio_Ibge as municipio_ibge,
    Municipio      as municipio,
    Estado_Ibge    as estado_ibge,
    Estado         as estado,
    Sigla_Regiao   as sigla_regiao,
    Regiao         as regiao,
    VL_PagadorPF   as vl_pagador_pf,
    QT_PagadorPF   as qt_pagador_pf,
    VL_PagadorPJ   as vl_pagador_pj,
    QT_PagadorPJ   as qt_pagador_pj,
    VL_RecebedorPF as vl_recebedor_pf,
    QT_RecebedorPF as qt_recebedor_pf,
    VL_RecebedorPJ as vl_recebedor_pj,
    QT_RecebedorPJ as qt_recebedor_pj,
    QT_PES_PagadorPF   as qt_pes_pagador_pf,
    QT_PES_PagadorPJ   as qt_pes_pagador_pj,
    QT_PES_RecebedorPF as qt_pes_recebedor_pf,
    QT_PES_RecebedorPJ as qt_pes_recebedor_pj
from source
