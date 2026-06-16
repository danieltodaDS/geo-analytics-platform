with source as (
    select * from {{ source('raw', 'olist_orders') }}
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
    SAFE_CAST(order_purchase_timestamp      AS TIMESTAMP) as order_purchase_timestamp,
    SAFE_CAST(order_approved_at             AS TIMESTAMP) as order_approved_at,
    SAFE_CAST(order_delivered_carrier_date  AS TIMESTAMP) as order_delivered_carrier_date,
    SAFE_CAST(order_delivered_customer_date AS TIMESTAMP) as order_delivered_customer_date,
    SAFE_CAST(order_estimated_delivery_date AS TIMESTAMP) as order_estimated_delivery_date
from deduped
