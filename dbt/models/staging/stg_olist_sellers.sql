with source as (
    select * from {{ ref('olist_sellers') }}
),

deduped as (
    select
        md5(
            coalesce(seller_id,                  '') || '|' ||
            coalesce(seller_zip_code_prefix,     '') || '|' ||
            coalesce(seller_city,                '') || '|' ||
            coalesce(seller_state,               '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
from deduped
