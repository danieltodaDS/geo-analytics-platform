with source as (
    select * from {{ ref('ibge_localidades') }}
)

select
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
from source
