with source as (
    select * from {{ source('raw', 'olist_customers') }}
),

deduped as (
    select
        md5(
            coalesce(customer_id,               '') || '|' ||
            coalesce(customer_unique_id,         '') || '|' ||
            coalesce(CAST(customer_zip_code_prefix AS STRING),   '') || '|' ||
            coalesce(customer_city,              '') || '|' ||
            coalesce(customer_state,             '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
from deduped
