with source as (
    select * from {{ ref('olist_orders') }}
),

deduped as (
    select * from source
    qualify row_number() over (
        partition by order_id, customer_id, order_status,
                     order_purchase_timestamp, order_approved_at,
                     order_delivered_carrier_date, order_delivered_customer_date,
                     order_estimated_delivery_date
    ) = 1
)

select
    order_id,
    customer_id,
    order_status,
    try_cast(order_purchase_timestamp      as timestamp) as order_purchase_timestamp,
    try_cast(order_approved_at             as timestamp) as order_approved_at,
    try_cast(order_delivered_carrier_date  as timestamp) as order_delivered_carrier_date,
    try_cast(order_delivered_customer_date as timestamp) as order_delivered_customer_date,
    try_cast(order_estimated_delivery_date as timestamp) as order_estimated_delivery_date
from deduped
