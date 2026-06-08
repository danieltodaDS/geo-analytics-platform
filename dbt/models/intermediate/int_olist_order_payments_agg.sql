with source as (
    select * from {{ ref('stg_olist_order_payments') }}
),

aggregated as (
    select
        order_id,
        sum(payment_value) filter (where payment_type = 'credit_card')        as credit_card_value,
        max(payment_installments) filter (where payment_type = 'credit_card') as credit_card_installments,
        sum(payment_value) filter (where payment_type = 'boleto')             as boleto_value,
        sum(payment_value) filter (where payment_type = 'voucher')            as voucher_value,
        sum(payment_value) filter (where payment_type = 'debit_card')         as debit_card_value,
        sum(payment_value) filter (where payment_type = 'not_defined')        as not_defined_value,
        sum(payment_value)                                                      as total_payment_value,
        count(distinct payment_type)                                            as payment_types_count
    from source
    group by order_id
)

select * from aggregated
