with source as (
    select * from {{ source('raw', 'olist_products') }}
),

deduped as (
    select
        md5(
            coalesce(product_id,                              '') || '|' ||
            coalesce(product_category_name,                   '') || '|' ||
            coalesce(CAST(product_name_lenght AS STRING),     '') || '|' ||
            coalesce(CAST(product_description_lenght AS STRING),'') || '|' ||
            coalesce(CAST(product_photos_qty AS STRING),      '') || '|' ||
            coalesce(CAST(product_weight_g AS STRING),        '') || '|' ||
            coalesce(CAST(product_length_cm AS STRING),       '') || '|' ||
            coalesce(CAST(product_height_cm AS STRING),       '') || '|' ||
            coalesce(CAST(product_width_cm AS STRING),        '')
        ) as row_hash,
        *
    from source
    qualify row_number() over (partition by row_hash) = 1
)

select
    row_hash,
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
