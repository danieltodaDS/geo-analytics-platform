select 1
from {{ ref('stg_olist_orders') }}
having count(*) < 90000
