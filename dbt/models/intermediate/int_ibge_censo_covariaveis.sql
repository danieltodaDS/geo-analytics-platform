with pop as (
    select
        codigo_municipio,
        ano,
        max(case when codigo_variavel = '93' then valor end) as populacao_residente
    from {{ ref('stg_ibge_censo_9514') }}
    group by codigo_municipio, ano
),

renda as (
    select
        codigo_municipio,
        max(case when codigo_variavel = '13431' then valor end) as renda_media_per_capita,
        max(case when codigo_variavel = '13534' then valor end) as renda_mediana_per_capita
    from {{ ref('stg_ibge_censo_10295') }}
    group by codigo_municipio
),

internet as (
    select
        codigo_municipio,
        pct_domicilios_com_internet
    from {{ ref('stg_ibge_censo_9936') }}
)

select
    pop.codigo_municipio,
    pop.ano                            as ano_censo,
    pop.populacao_residente,
    renda.renda_media_per_capita,
    renda.renda_mediana_per_capita,
    internet.pct_domicilios_com_internet
from pop
left join renda   on pop.codigo_municipio = renda.codigo_municipio
left join internet on pop.codigo_municipio = internet.codigo_municipio
