with source as (
    select * from {{ ref('ibge_censo_9936') }}
)

select
    md5(
        coalesce(D1C, '') || '|' ||
        coalesce(D2C, '') || '|' ||
        coalesce(D3C, '') || '|' ||
        coalesce(D4C, '') || '|' ||
        coalesce(V,   '')
    )                            as row_hash,
    try_cast(D1C as bigint)      as codigo_municipio,
    try_cast(D3C as bigint)      as ano,
    try_cast(V as double)        as pct_domicilios_com_internet
from source
qualify row_number() over (partition by row_hash) = 1
