with source as (
    select * from {{ ref('ibge_censo_9605') }}
)

select
    md5(
        coalesce(D1C, '') || '|' ||
        coalesce(D2C, '') || '|' ||
        coalesce(D2N, '') || '|' ||
        coalesce(D3C, '') || '|' ||
        coalesce(D4C, '') || '|' ||
        coalesce(D4N, '') || '|' ||
        coalesce(V,   '')
    )                            as row_hash,
    try_cast(D1C as bigint)      as codigo_municipio,
    D2C                          as codigo_variavel,
    D2N                          as variavel,
    try_cast(D3C as bigint)      as ano,
    D4C                          as codigo_cor_raca,
    D4N                          as cor_raca,
    try_cast(V as double)        as valor
from source
qualify row_number() over (partition by row_hash) = 1
