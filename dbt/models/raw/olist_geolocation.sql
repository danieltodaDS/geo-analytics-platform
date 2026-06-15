select * from {{ source('landing', 'olist_geolocation') }}
