with source as (
    select * from {{ ref('olist_order_items') }}
),

deduped as (
    select
        md5(
            coalesce(order_id,                       '') || '|' ||
            coalesce(order_item_id::varchar,         '') || '|' ||
            coalesce(product_id,                     '') || '|' ||
            coalesce(seller_id,                      '') || '|' ||
            coalesce(shipping_limit_date,            '') || '|' ||
            coalesce(price::varchar,                 '') || '|' ||
            coalesce(freight_value::varchar,         '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    order_id || '-' || order_item_id::varchar        as order_item_pk,
    order_id,
    order_item_id,
    product_id,
    seller_id,
    try_cast(shipping_limit_date as timestamp)       as shipping_limit_date,
    price,
    freight_value
from deduped
