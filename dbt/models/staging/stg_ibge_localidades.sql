with source as (
    select * from {{ ref('ibge_localidades') }}
),

deduped as (
    select
        md5(
            coalesce(id_municipio::varchar,      '') || '|' ||
            coalesce(nome_municipio,             '') || '|' ||
            coalesce(regiao_imediata_id::varchar,'') || '|' ||
            coalesce(regiao_imediata_nome,       '') || '|' ||
            coalesce(regiao_interm_id::varchar,  '') || '|' ||
            coalesce(regiao_interm_nome,         '') || '|' ||
            coalesce(uf_id::varchar,             '') || '|' ||
            coalesce(uf_sigla,                   '') || '|' ||
            coalesce(uf_nome,                    '') || '|' ||
            coalesce(macroregiao_id::varchar,    '') || '|' ||
            coalesce(macroregiao_sigla,          '') || '|' ||
            coalesce(macroregiao_nome,           '') || '|' ||
            coalesce(microrregiao_id::varchar,   '') || '|' ||
            coalesce(microrregiao_nome,          '') || '|' ||
            coalesce(mesorregiao_id::varchar,    '') || '|' ||
            coalesce(mesorregiao_nome,           '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    id_municipio,
    nome_municipio,
    regiao_imediata_id,
    regiao_imediata_nome,
    regiao_interm_id,
    regiao_interm_nome,
    uf_id,
    uf_sigla,
    uf_nome,
    macroregiao_id,
    macroregiao_sigla,
    macroregiao_nome,
    try_cast(microrregiao_id as integer) as microrregiao_id,
    microrregiao_nome,
    try_cast(mesorregiao_id as integer)  as mesorregiao_id,
    mesorregiao_nome
from deduped
