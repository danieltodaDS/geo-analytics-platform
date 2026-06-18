with source as (
    select * from {{ source('raw', 'ibge_censo_9936') }}
    where ingestion_date = (
        select max(ingestion_date) from {{ source('raw', 'ibge_censo_9936') }}
    )
)

select
    md5(
        coalesce(D1C, '') || '|' ||
        coalesce(D2C, '') || '|' ||
        coalesce(D3C, '') || '|' ||
        coalesce(D4C, '') || '|' ||
        coalesce(V,   '')
    )                                  as row_hash,
    SAFE_CAST(D1C AS INT64)            as codigo_municipio,
    SAFE_CAST(D3C AS INT64)            as ano,
    SAFE_CAST(V AS FLOAT64)            as pct_domicilios_com_internet
from source
qualify row_number() over (partition by row_hash) = 1
