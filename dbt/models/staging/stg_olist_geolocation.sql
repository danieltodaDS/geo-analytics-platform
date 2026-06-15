with source as (
    select * from {{ ref('olist_geolocation') }}
),

deduped as (
    select
        md5(
            coalesce(CAST(geolocation_zip_code_prefix AS STRING),        '') || '|' ||
            coalesce(CAST(geolocation_lat AS STRING),    '') || '|' ||
            coalesce(CAST(geolocation_lng AS STRING),    '') || '|' ||
            coalesce(geolocation_city,                   '') || '|' ||
            coalesce(geolocation_state,                  '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
from deduped
