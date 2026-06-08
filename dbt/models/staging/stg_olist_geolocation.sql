with source as (
    select * from {{ ref('olist_geolocation') }}
),

deduped as (
    select * from source
    qualify row_number() over (
        partition by geolocation_zip_code_prefix, geolocation_lat,
                     geolocation_lng, geolocation_city, geolocation_state
    ) = 1
)

select
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
from deduped
