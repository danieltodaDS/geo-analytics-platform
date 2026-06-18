with source as (
    select * from {{ source('raw', 'ibge_censo_9514') }}
    where ingestion_date = (
        select max(ingestion_date) from {{ source('raw', 'ibge_censo_9514') }}
    )
)

select
    md5(
        coalesce(D1C, '') || '|' ||
        coalesce(D2C, '') || '|' ||
        coalesce(D2N, '') || '|' ||
        coalesce(D3C, '') || '|' ||
        coalesce(D4C, '') || '|' ||
        coalesce(D4N, '') || '|' ||
        coalesce(D5C, '') || '|' ||
        coalesce(D5N, '') || '|' ||
        coalesce(D6C, '') || '|' ||
        coalesce(D6N, '') || '|' ||
        coalesce(V,   '')
    )                                   as row_hash,
    SAFE_CAST(D1C AS INT64)             as codigo_municipio,
    D2C                                 as codigo_variavel,
    D2N                                 as variavel,
    SAFE_CAST(D3C AS INT64)             as ano,
    D4C                                 as codigo_sexo,
    D4N                                 as sexo,
    D5C                                 as codigo_declaracao_idade,
    D5N                                 as declaracao_idade,
    D6C                                 as codigo_idade,
    D6N                                 as idade,
    SAFE_CAST(V AS FLOAT64)             as valor
from source
qualify row_number() over (partition by row_hash) = 1
