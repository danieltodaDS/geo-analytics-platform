with source as (
    select * from {{ ref('ibge_censo_9605') }}
)

select
    md5(D1C || '|' || D2C || '|' || D4C) as surrogate_key,
    try_cast(D1C as bigint) as codigo_municipio,
    D2C                     as codigo_variavel,
    D2N                     as variavel,
    try_cast(D3C as bigint) as ano,
    D4C                     as codigo_cor_raca,
    D4N                     as cor_raca,
    try_cast(V as double)   as valor
from source
