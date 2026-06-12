with items as (
    select * from {{ ref('stg_olist_order_items') }}
),

products as (
    select
        product_id,
        product_category_name
    from {{ ref('stg_olist_products') }}
),

enriched as (
    select
        i.order_id,
        i.order_item_id,
        i.product_id,
        i.seller_id,
        i.price,
        i.freight_value,
        p.product_category_name
    from items i
    left join products p on i.product_id = p.product_id
),

aggregated as (
    select
        order_id,
        count(order_item_id)             as items_count,
        count(distinct product_id)       as unique_products_count,
        count(distinct seller_id)        as unique_sellers_count,
        sum(price)                       as total_price,
        sum(freight_value)               as total_freight_value,
        sum(price) + sum(freight_value)  as total_revenue,
        mode(product_category_name)      as dominant_category_name
    from enriched
    group by order_id
)

select * from aggregated
