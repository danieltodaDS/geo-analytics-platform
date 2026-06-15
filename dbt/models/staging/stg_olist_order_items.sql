with source as (
    select * from {{ ref('olist_order_items') }}
),

deduped as (
    select
        md5(
            coalesce(order_id,                           '') || '|' ||
            coalesce(CAST(order_item_id AS STRING),      '') || '|' ||
            coalesce(product_id,                         '') || '|' ||
            coalesce(seller_id,                          '') || '|' ||
            coalesce(shipping_limit_date,                '') || '|' ||
            coalesce(CAST(price AS STRING),              '') || '|' ||
            coalesce(CAST(freight_value AS STRING),      '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    order_id || '-' || CAST(order_item_id AS STRING)  as order_item_pk,
    order_id,
    order_item_id,
    product_id,
    seller_id,
    SAFE_CAST(shipping_limit_date AS TIMESTAMP)        as shipping_limit_date,
    price,
    freight_value
from deduped
