with customers as (
    select * from {{ ref('stg_olist_customers') }}
),

geolocation as (
    select
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng
    from {{ ref('int_olist_geolocation') }}
),

canonical as (
    select
        customer_unique_id,
        {{ compat_mode('customer_zip_code_prefix') }}  as customer_zip_code_prefix,
        {{ compat_mode('customer_state') }}            as customer_state,
        {{ compat_mode('customer_city') }}             as customer_city
    from customers
    group by customer_unique_id
)

select
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_state,
    c.customer_city,
    {{ normalize_city_name('c.customer_city') }} as customer_city_slug,
    g.geolocation_lat  as customer_lat,
    g.geolocation_lng  as customer_lng
from canonical c
left join geolocation g
    on c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
