#!/usr/bin/env bash
# Executar uma vez no provisionamento. Requer ADC autenticada e bq configurado.
set -euo pipefail

PROJECT=data-pipeline-lab-497514
BUCKET=geo-analytics-platform-raw

tables=(
  olist_customers
  olist_orders
  olist_order_items
  olist_order_payments
  olist_order_reviews
  olist_geolocation
  olist_products
  olist_sellers
  ibge_localidades
  ibge_censo_9514
  ibge_censo_10295
  ibge_censo_9936
  bcb_pix
)

for table in "${tables[@]}"; do
  echo "Criando External Table: raw.${table}"
  bq query --nouse_legacy_sql --project_id="${PROJECT}" << EOF
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT}.raw.${table}\`
WITH PARTITION COLUMNS (year INT64, month INT64, day INT64)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://${BUCKET}/raw/${table}/*/*/*.parquet'],
  hive_partition_uri_prefix = 'gs://${BUCKET}/raw/${table}',
  require_hive_partition_filter = false
)
EOF
done

echo "=== Verificação ==="
bq query --nouse_legacy_sql \
  "SELECT COUNT(*) as n FROM \`${PROJECT}.raw.olist_orders\`"
# Esperado: 99.441
