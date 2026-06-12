with source as (
    select * from {{ ref('olist_order_reviews') }}
),

deduped as (
    select
        md5(
            coalesce(review_id,                         '') || '|' ||
            coalesce(order_id,                          '') || '|' ||
            coalesce(CAST(review_score AS STRING),      '') || '|' ||
            coalesce(review_comment_title,              '') || '|' ||
            coalesce(review_comment_message,            '') || '|' ||
            coalesce(review_creation_date,              '') || '|' ||
            coalesce(review_answer_timestamp,           '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    review_id || '-' || order_id                        as review_pk,
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    SAFE_CAST(review_creation_date    AS TIMESTAMP)     as review_creation_date,
    SAFE_CAST(review_answer_timestamp AS TIMESTAMP)     as review_answer_timestamp
from deduped
