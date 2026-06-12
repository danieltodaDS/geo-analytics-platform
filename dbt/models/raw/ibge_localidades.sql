select * from {{ source('parquet_files', 'ibge_localidades') }}
