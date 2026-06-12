select * from {{ source('parquet_files', 'bcb_pix') }}
