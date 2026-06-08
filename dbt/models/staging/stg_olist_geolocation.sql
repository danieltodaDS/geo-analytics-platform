with source as (
    select * from {{ ref('olist_geolocation') }}
),

deduped as (
    select
        md5(
            coalesce(geolocation_zip_code_prefix,    '') || '|' ||
            coalesce(geolocation_lat::varchar,       '') || '|' ||
            coalesce(geolocation_lng::varchar,       '') || '|' ||
            coalesce(geolocation_city,               '') || '|' ||
            coalesce(geolocation_state,              '')
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
