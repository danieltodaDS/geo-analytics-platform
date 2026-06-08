with source as (
    select * from {{ ref('olist_order_items') }}
)

select
    order_id || '-' || order_item_id::varchar as order_item_pk,
    order_id,
    order_item_id,
    product_id,
    seller_id,
    try_cast(shipping_limit_date as timestamp) as shipping_limit_date,
    price,
    freight_value
from source
