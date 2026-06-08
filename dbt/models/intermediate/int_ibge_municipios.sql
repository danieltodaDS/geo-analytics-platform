with localidades as (
    select * from {{ ref('stg_ibge_localidades') }}
),

covariaveis as (
    select * from {{ ref('int_ibge_censo_covariaveis') }}
)

select
    localidades.id_municipio,
    localidades.nome_municipio,
    localidades.uf_sigla,
    localidades.uf_nome,
    localidades.macroregiao_sigla,
    localidades.macroregiao_nome,
    covariaveis.ano_censo,
    covariaveis.populacao_residente,
    covariaveis.renda_media_per_capita,
    covariaveis.renda_mediana_per_capita,
    covariaveis.pct_domicilios_com_internet
from localidades
left join covariaveis on localidades.id_municipio = covariaveis.codigo_municipio
