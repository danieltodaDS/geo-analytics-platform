with source as (
    select * from {{ ref('olist_products') }}
),

deduped as (
    select * from source
    qualify row_number() over (
        partition by product_id, product_category_name, product_name_lenght,
                     product_description_lenght, product_photos_qty, product_weight_g,
                     product_length_cm, product_height_cm, product_width_cm
    ) = 1
)

select
    product_id,
    product_category_name,
    product_name_lenght        as product_name_length,
    product_description_lenght as product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
from deduped
