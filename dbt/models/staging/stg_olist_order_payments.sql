with source as (
    select * from {{ ref('olist_order_payments') }}
),

deduped as (
    select * from source
    qualify row_number() over (
        partition by order_id, payment_sequential, payment_type,
                     payment_installments, payment_value
    ) = 1
)

select
    order_id || '-' || payment_sequential::varchar   as payment_pk,
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
from deduped
