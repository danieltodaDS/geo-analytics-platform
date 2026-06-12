with orders as (
    select * from {{ ref('stg_olist_orders') }}
),

customers as (
    select
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_state,
        customer_city
    from {{ ref('stg_olist_customers') }}
),

geolocation as (
    select
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng
    from {{ ref('int_olist_geolocation') }}
),

payments as (
    select * from {{ ref('int_olist_order_payments_agg') }}
),

items as (
    select * from {{ ref('int_olist_order_items_agg') }}
),

reviews as (
    select * from {{ ref('int_olist_order_reviews_agg') }}
),

joined as (
    select
        -- identifiers
        o.order_id,
        o.customer_id,
        c.customer_unique_id,
        o.order_status,

        -- timestamps
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,

        -- customer geography (order-time)
        c.customer_zip_code_prefix,
        c.customer_state,
        c.customer_city,
        g.geolocation_lat                                                               as customer_lat,
        g.geolocation_lng                                                               as customer_lng,

        -- delivery metrics
        datediff('day', o.order_purchase_timestamp, o.order_approved_at)               as approval_days,
        datediff('day', o.order_purchase_timestamp, o.order_estimated_delivery_date)   as estimated_delivery_days,
        datediff('day', o.order_purchase_timestamp, o.order_delivered_customer_date)   as delivery_days,
        case
            when o.order_delivered_customer_date is null then null
            else o.order_delivered_customer_date <= o.order_estimated_delivery_date
        end                                                                             as is_on_time,

        -- payments
        p.total_payment_value,
        p.credit_card_value,
        p.credit_card_installments,
        p.boleto_value,
        p.voucher_value,
        p.debit_card_value,
        p.not_defined_value,
        p.payment_types_count,

        -- items
        i.items_count,
        i.unique_products_count,
        i.unique_sellers_count,
        i.total_price,
        i.total_freight_value,
        i.total_revenue,
        i.dominant_category_name,

        -- reviews
        r.review_score,
        r.has_comment

    from orders o
    inner join customers  c on o.customer_id              = c.customer_id
    left join  geolocation g on c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
    left join  payments    p on o.order_id                 = p.order_id
    left join  items       i on o.order_id                 = i.order_id
    left join  reviews     r on o.order_id                 = r.order_id
)

select * from joined
