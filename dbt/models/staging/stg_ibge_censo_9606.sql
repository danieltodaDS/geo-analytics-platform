with source as (
    select * from {{ ref('ibge_censo_9606') }}
)

select
    md5(D1C || '|' || D2C || '|' || D4C || '|' || D5C || '|' || D6C) as surrogate_key,
    try_cast(D1C as bigint) as codigo_municipio,
    D2C                     as codigo_variavel,
    D2N                     as variavel,
    try_cast(D3C as bigint) as ano,
    D4C                     as codigo_sexo,
    D4N                     as sexo,
    D5C                     as codigo_cor_raca,
    D5N                     as cor_raca,
    D6C                     as codigo_idade,
    D6N                     as idade,
    try_cast(V as double)   as valor
from source
