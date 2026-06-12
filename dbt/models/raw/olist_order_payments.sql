select * from {{ source('parquet_files', 'olist_order_payments') }}
