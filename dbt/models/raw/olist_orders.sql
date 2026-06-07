select * from {{ source('parquet_files', 'olist_orders') }}
