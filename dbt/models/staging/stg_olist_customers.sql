with source as (
    select * from {{ ref('olist_customers') }}
),

deduped as (
    select * from source
    qualify row_number() over (
        partition by customer_id, customer_unique_id, customer_zip_code_prefix,
                     customer_city, customer_state
    ) = 1
)

select
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
from deduped
