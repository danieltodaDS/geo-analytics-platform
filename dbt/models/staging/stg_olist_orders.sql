with source as (
    select * from {{ ref('olist_orders') }}
),

deduped as (
    select
        md5(
            coalesce(order_id,                        '') || '|' ||
            coalesce(customer_id,                     '') || '|' ||
            coalesce(order_status,                    '') || '|' ||
            coalesce(order_purchase_timestamp,        '') || '|' ||
            coalesce(order_approved_at,               '') || '|' ||
            coalesce(order_delivered_carrier_date,    '') || '|' ||
            coalesce(order_delivered_customer_date,   '') || '|' ||
            coalesce(order_estimated_delivery_date,   '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    order_id,
    customer_id,
    order_status,
    try_cast(order_purchase_timestamp      as timestamp) as order_purchase_timestamp,
    try_cast(order_approved_at             as timestamp) as order_approved_at,
    try_cast(order_delivered_carrier_date  as timestamp) as order_delivered_carrier_date,
    try_cast(order_delivered_customer_date as timestamp) as order_delivered_customer_date,
    try_cast(order_estimated_delivery_date as timestamp) as order_estimated_delivery_date
from deduped
