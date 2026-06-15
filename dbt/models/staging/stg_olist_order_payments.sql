with source as (
    select * from {{ ref('olist_order_payments') }}
),

deduped as (
    select
        md5(
            coalesce(order_id,                              '') || '|' ||
            coalesce(CAST(payment_sequential AS STRING),    '') || '|' ||
            coalesce(payment_type,                          '') || '|' ||
            coalesce(CAST(payment_installments AS STRING),  '') || '|' ||
            coalesce(CAST(payment_value AS STRING),         '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    order_id || '-' || CAST(payment_sequential AS STRING)  as payment_pk,
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
from deduped
