with source as (
    select * from {{ ref('stg_olist_geolocation') }}
),

centroide as (
    select
        geolocation_zip_code_prefix,
        avg(geolocation_lat)                  as geolocation_lat,
        avg(geolocation_lng)                  as geolocation_lng,
        {{ compat_mode('geolocation_city') }}  as geolocation_city,
        {{ compat_mode('geolocation_state') }} as geolocation_state
    from source
    group by geolocation_zip_code_prefix
)

select
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    {{ normalize_city_name('geolocation_city') }} as geolocation_city_slug,
    geolocation_state
from centroide
