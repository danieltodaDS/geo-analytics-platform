with source as (
    select * from {{ ref('olist_order_payments') }}
),

deduped as (
    select
        md5(
            coalesce(order_id,                       '') || '|' ||
            coalesce(payment_sequential::varchar,    '') || '|' ||
            coalesce(payment_type,                   '') || '|' ||
            coalesce(payment_installments::varchar,  '') || '|' ||
            coalesce(payment_value::varchar,         '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    order_id || '-' || payment_sequential::varchar   as payment_pk,
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
from deduped
