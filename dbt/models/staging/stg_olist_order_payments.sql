with source as (
    select * from {{ ref('olist_order_payments') }}
)

select
    order_id || '-' || payment_sequential::varchar as payment_pk,
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
from source
