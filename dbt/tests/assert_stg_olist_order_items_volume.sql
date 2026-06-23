select 1
from (select count(*) as total from {{ ref('stg_olist_order_items') }})
where total < 100000
