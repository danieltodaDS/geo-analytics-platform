select 1
from {{ ref('stg_olist_order_items') }}
having count(*) < 100000
