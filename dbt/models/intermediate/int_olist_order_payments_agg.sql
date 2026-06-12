with source as (
    select * from {{ ref('stg_olist_order_payments') }}
),

aggregated as (
    select
        order_id,
        sum(if(payment_type = 'credit_card', payment_value, null))        as credit_card_value,
        max(if(payment_type = 'credit_card', payment_installments, null)) as credit_card_installments,
        sum(if(payment_type = 'boleto', payment_value, null))             as boleto_value,
        sum(if(payment_type = 'voucher', payment_value, null))            as voucher_value,
        sum(if(payment_type = 'debit_card', payment_value, null))         as debit_card_value,
        sum(if(payment_type = 'not_defined', payment_value, null))        as not_defined_value,
        sum(payment_value)                                                  as total_payment_value,
        count(distinct payment_type)                                        as payment_types_count
    from source
    group by order_id
)

select * from aggregated
