with source as (
    select * from {{ ref('olist_sellers') }}
),

deduped as (
    select * from source
    qualify row_number() over (
        partition by seller_id, seller_zip_code_prefix, seller_city, seller_state
    ) = 1
)

select
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
from deduped
