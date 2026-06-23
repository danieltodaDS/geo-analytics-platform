select 1
from {{ ref('stg_olist_customers') }}
having count(*) < 90000
