with source as (
    select * from {{ source('raw', 'ibge_localidades') }}
    where ingestion_date = (
        select max(ingestion_date) from {{ source('raw', 'ibge_localidades') }}
    )
),

deduped as (
    select
        md5(
            coalesce(CAST(id_municipio AS STRING),       '') || '|' ||
            coalesce(nome_municipio,                     '') || '|' ||
            coalesce(CAST(regiao_imediata_id AS STRING), '') || '|' ||
            coalesce(regiao_imediata_nome,               '') || '|' ||
            coalesce(CAST(regiao_interm_id AS STRING),   '') || '|' ||
            coalesce(regiao_interm_nome,                 '') || '|' ||
            coalesce(CAST(uf_id AS STRING),              '') || '|' ||
            coalesce(uf_sigla,                           '') || '|' ||
            coalesce(uf_nome,                            '') || '|' ||
            coalesce(CAST(macroregiao_id AS STRING),     '') || '|' ||
            coalesce(macroregiao_sigla,                  '') || '|' ||
            coalesce(macroregiao_nome,                   '') || '|' ||
            coalesce(CAST(microrregiao_id AS STRING),    '') || '|' ||
            coalesce(microrregiao_nome,                  '') || '|' ||
            coalesce(CAST(mesorregiao_id AS STRING),     '') || '|' ||
            coalesce(mesorregiao_nome,                   '')
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
    SAFE_CAST(microrregiao_id AS INT64) as microrregiao_id,
    microrregiao_nome,
    SAFE_CAST(mesorregiao_id AS INT64)  as mesorregiao_id,
    mesorregiao_nome
from deduped
