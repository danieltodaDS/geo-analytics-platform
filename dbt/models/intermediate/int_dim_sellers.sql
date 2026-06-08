with sellers as (
    select * from {{ ref('stg_olist_sellers') }}
),

geolocation as (
    select
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng
    from {{ ref('int_olist_geolocation') }}
)

select
    s.seller_id,
    s.seller_zip_code_prefix,
    s.seller_state,
    s.seller_city,
    g.geolocation_lat  as seller_lat,
    g.geolocation_lng  as seller_lng
from sellers s
left join geolocation g
    on s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
