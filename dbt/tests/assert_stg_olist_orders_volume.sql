select 1
from (select count(*) as total from {{ ref('stg_olist_orders') }})
where total < 90000
