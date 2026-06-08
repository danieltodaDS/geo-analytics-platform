with source as (
    select * from {{ ref('stg_olist_order_reviews') }}
),

latest_per_order as (
    select
        order_id,
        review_score,
        review_comment_message is not null  as has_comment
    from source
    qualify row_number() over (
        partition by order_id
        order by review_answer_timestamp desc nulls last
    ) = 1
)

select * from latest_per_order
