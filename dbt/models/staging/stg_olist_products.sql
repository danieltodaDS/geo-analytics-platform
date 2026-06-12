with source as (
    select * from {{ ref('olist_products') }}
),

deduped as (
    select
        md5(
            coalesce(product_id,                         '') || '|' ||
            coalesce(product_category_name,              '') || '|' ||
            coalesce(product_name_lenght::varchar,       '') || '|' ||
            coalesce(product_description_lenght::varchar,'') || '|' ||
            coalesce(product_photos_qty::varchar,        '') || '|' ||
            coalesce(product_weight_g::varchar,          '') || '|' ||
            coalesce(product_length_cm::varchar,         '') || '|' ||
            coalesce(product_height_cm::varchar,         '') || '|' ||
            coalesce(product_width_cm::varchar,          '')
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
