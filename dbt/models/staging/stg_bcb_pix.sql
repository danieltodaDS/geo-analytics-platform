with source as (
    select * from {{ ref('bcb_pix') }}
)

select
    md5(
        coalesce(AnoMes::varchar,            '') || '|' ||
        coalesce(Municipio_Ibge::varchar,    '') || '|' ||
        coalesce(Municipio,                  '') || '|' ||
        coalesce(Estado_Ibge::varchar,       '') || '|' ||
        coalesce(Estado,                     '') || '|' ||
        coalesce(Sigla_Regiao,               '') || '|' ||
        coalesce(Regiao,                     '') || '|' ||
        coalesce(VL_PagadorPF::varchar,      '') || '|' ||
        coalesce(QT_PagadorPF::varchar,      '') || '|' ||
        coalesce(VL_PagadorPJ::varchar,      '') || '|' ||
        coalesce(QT_PagadorPJ::varchar,      '') || '|' ||
        coalesce(VL_RecebedorPF::varchar,    '') || '|' ||
        coalesce(QT_RecebedorPF::varchar,    '') || '|' ||
        coalesce(VL_RecebedorPJ::varchar,    '') || '|' ||
        coalesce(QT_RecebedorPJ::varchar,    '') || '|' ||
        coalesce(QT_PES_PagadorPF::varchar,  '') || '|' ||
        coalesce(QT_PES_PagadorPJ::varchar,  '') || '|' ||
        coalesce(QT_PES_RecebedorPF::varchar,'') || '|' ||
        coalesce(QT_PES_RecebedorPJ::varchar,'')
    )                      as row_hash,
    AnoMes                 as ano_mes,
    Municipio_Ibge         as municipio_ibge,
    Municipio              as municipio,
    Estado_Ibge            as estado_ibge,
    Estado                 as estado,
    Sigla_Regiao           as sigla_regiao,
    Regiao                 as regiao,
    VL_PagadorPF           as vl_pagador_pf,
    QT_PagadorPF           as qt_pagador_pf,
    VL_PagadorPJ           as vl_pagador_pj,
    QT_PagadorPJ           as qt_pagador_pj,
    VL_RecebedorPF         as vl_recebedor_pf,
    QT_RecebedorPF         as qt_recebedor_pf,
    VL_RecebedorPJ         as vl_recebedor_pj,
    QT_RecebedorPJ         as qt_recebedor_pj,
    QT_PES_PagadorPF       as qt_pes_pagador_pf,
    QT_PES_PagadorPJ       as qt_pes_pagador_pj,
    QT_PES_RecebedorPF     as qt_pes_recebedor_pf,
    QT_PES_RecebedorPJ     as qt_pes_recebedor_pj
from source
qualify row_number() over (partition by row_hash) = 1
