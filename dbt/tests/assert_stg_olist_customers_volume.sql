select 1
from (select count(*) as total from {{ ref('stg_olist_customers') }})
where total < 90000
