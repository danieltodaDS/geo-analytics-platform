with source as (
    select * from {{ ref('olist_order_reviews') }}
),

deduped as (
    select
        md5(
            coalesce(review_id,                  '') || '|' ||
            coalesce(order_id,                   '') || '|' ||
            coalesce(review_score::varchar,      '') || '|' ||
            coalesce(review_comment_title,       '') || '|' ||
            coalesce(review_comment_message,     '') || '|' ||
            coalesce(review_creation_date,       '') || '|' ||
            coalesce(review_answer_timestamp,    '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    review_id || '-' || order_id                     as review_pk,
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    try_cast(review_creation_date    as timestamp)   as review_creation_date,
    try_cast(review_answer_timestamp as timestamp)   as review_answer_timestamp
from deduped
