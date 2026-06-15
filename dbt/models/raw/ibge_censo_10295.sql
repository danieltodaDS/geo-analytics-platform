select * from {{ source('landing', 'ibge_censo_10295') }}
