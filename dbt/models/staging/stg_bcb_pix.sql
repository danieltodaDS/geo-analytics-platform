with source as (
    select * from {{ source('raw', 'bcb_pix') }}
    where ingestion_date = (
        select max(ingestion_date) from {{ source('raw', 'bcb_pix') }}
    )
)

select
    md5(
        coalesce(CAST(AnoMes AS STRING),             '') || '|' ||
        coalesce(CAST(Municipio_Ibge AS STRING),     '') || '|' ||
        coalesce(Municipio,                          '') || '|' ||
        coalesce(CAST(Estado_Ibge AS STRING),        '') || '|' ||
        coalesce(Estado,                             '') || '|' ||
        coalesce(Sigla_Regiao,                       '') || '|' ||
        coalesce(Regiao,                             '') || '|' ||
        coalesce(CAST(VL_PagadorPF AS STRING),       '') || '|' ||
        coalesce(CAST(QT_PagadorPF AS STRING),       '') || '|' ||
        coalesce(CAST(VL_PagadorPJ AS STRING),       '') || '|' ||
        coalesce(CAST(QT_PagadorPJ AS STRING),       '') || '|' ||
        coalesce(CAST(VL_RecebedorPF AS STRING),     '') || '|' ||
        coalesce(CAST(QT_RecebedorPF AS STRING),     '') || '|' ||
        coalesce(CAST(VL_RecebedorPJ AS STRING),     '') || '|' ||
        coalesce(CAST(QT_RecebedorPJ AS STRING),     '') || '|' ||
        coalesce(CAST(QT_PES_PagadorPF AS STRING),   '') || '|' ||
        coalesce(CAST(QT_PES_PagadorPJ AS STRING),   '') || '|' ||
        coalesce(CAST(QT_PES_RecebedorPF AS STRING), '') || '|' ||
        coalesce(CAST(QT_PES_RecebedorPJ AS STRING), '')
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
