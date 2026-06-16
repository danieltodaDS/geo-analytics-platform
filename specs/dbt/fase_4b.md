# Spec — Fase 4b: Migração dbt-duckdb → dbt-bigquery

> Pré-requisito: `docs/understanding/fase_4b.md` lido na íntegra.
> Base normativa: ADR-001, ADR-007, ADR-008, `conventions.md`, `data_quality.md`.
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da fase

```
O que muda:     Adapter dbt (dbt-duckdb → dbt-bigquery)
                profiles.yml (DuckDB local → BigQuery OAuth)
                _sources.yml (parquet_files external → dataset landing no BigQuery)
                Dataset landing criado no BigQuery (zona de ingestão / datalake local)
                make bq-load: 13 Parquets carregados em landing.*
                7 modelos staging (TRY_CAST → SAFE_CAST, ::cast → CAST)
                5 modelos intermediate (débitos de dialeto SQL)
                Marts (cast as double → CAST AS FLOAT64)
                Streamlit (DuckDB → google-cloud-bigquery)
                3 macros cross-db (compat_datediff, compat_mode, normalize_city_name)

O que NÃO muda: Parquets em data/raw/ — permanecem locais (GCS é fase 4c)
                Lógica de negócio de todos os modelos
                Estrutura de camadas raw → staging → intermediate → marts
                Suite de testes completa (_staging.yml, _intermediate.yml, _marts.yml)
```

---

## Pré-requisitos

- Datasets BigQuery criados: `landing`, `raw`, `staging`, `intermediate`, `marts` (`make setup-gcloud` executado)
- ADC autenticada: `make auth`
- Parquets em `data/raw/` completos (ingestão fase 4a concluída)

---

## Arquitetura de datasets — decisão e rationale

### O problema do namespace compartilhado

Em DuckDB (fase 4a), a raw layer é um conjunto de VIEWs que leem diretamente dos Parquets via `read_parquet(...)`. O "datalake" é o **filesystem** — existe fora de qualquer namespace SQL. Não há conflito possível entre a source e a view dbt que a consome.

```
filesystem (data/raw/**/*.parquet)   ← fora do namespace DuckDB
        ↓ read_parquet
raw.olist_customers  (VIEW dbt)      ← namespace DuckDB
```

No BigQuery, não existe filesystem acessível ao engine. Para que o dbt leia os Parquets, é preciso carregá-los via `bq load` — que cria **tabelas físicas dentro de um dataset BigQuery**. Se esse dataset for `raw`, as tabelas (`raw.olist_customers`) colidem com as views dbt (`raw.olist_customers`) no mesmo namespace.

### Decisão: dataset `landing` como zona de ingestão

O `bq load` carrega os Parquets no dataset `landing`. O dataset `raw` continua sendo gerenciado exclusivamente pelo dbt como camada de VIEWs — exatamente o mesmo papel que tinha no DuckDB.

```
landing.olist_customers  (TABLE — bq load, fora do dbt)
        ↓ source('landing', ...)
raw.olist_customers      (VIEW dbt — espelho fiel, sem transformação)
        ↓ ref('olist_customers')
staging.stg_olist_customers  (TABLE dbt)
```

O `landing` é uma **zona de ingestão temporária** — dados brutos chegam aqui antes de qualquer modelagem. O `raw` mantém seu contrato: view que espelha o datalake, zero transformação.

### Transição para fase 4c

Na fase 4c, os Parquets migram para GCS. O dataset `landing` é eliminado. O dataset `raw` passa a conter **External Tables** apontando diretamente para o GCS — eliminando tanto o `bq load` quanto os dbt raw views.

```
GCS gs://geo-analytics-platform-raw/raw/{fonte}/year=YYYY/...
        ↓ BigQuery External Table
raw.olist_customers  (EXTERNAL TABLE — substitui landing + raw view)
        ↓ source('raw', ...)
staging.stg_olist_customers
```

**Mudanças na transição 4b → 4c:**
- Dataset `landing` eliminado
- 13 arquivos `models/raw/*.sql` eliminados
- `_sources.yml`: `source: landing` → `source: raw`
- 13 modelos staging: `{{ ref('table') }}` → `{{ source('raw', 'table') }}`
- Intermediate e marts: sem alteração

---

## Sequência de implementação

### Passo 1 — Branch e tag

```bash
git checkout -b feat/fase-4b-bigquery
git tag v0.1-fase-4a
```

A branch isola o trabalho em progresso do `main` durante as múltiplas etapas destrutivas (remoção do adapter, ~20 arquivos editados). A tag marca o estado final da fase 4a como ponto de retorno seguro.

---

### Passo 2 — Criar dataset `landing` no BigQuery

```bash
bq mk --dataset --location=US data-pipeline-lab-497514:landing
```

O dataset `landing` é a zona de ingestão / datalake local da fase 4b. Os datasets `raw`, `staging`, `intermediate` e `marts` já existem do `make setup-gcloud`.

> Atualizar `make setup-gcloud` no Makefile para incluir a criação do dataset `landing`.

---

### Passo 3 — Troca de adapter e dependências

```bash
uv remove dbt-duckdb
uv add dbt-bigquery
uv add google-cloud-bigquery
```

> Após este passo, `dbt run` contra o profile DuckDB existente quebra — esperado.
> Não executar `dbt` até o profiles.yml estar atualizado (Passo 5).

---

### Passo 4 — Carga dos Parquets no BigQuery (`make bq-load`)

Destino: dataset `landing` — zona de ingestão fora do controle do dbt.
Ver decisão arquitetural acima para o racional.

Adicionar target ao Makefile:

```makefile
bq-load:
	bq load --replace --autodetect --source_format=PARQUET landing.olist_customers \
		$(shell find data/raw/olist_customers -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_orders \
		$(shell find data/raw/olist_orders -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_order_items \
		$(shell find data/raw/olist_order_items -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_order_payments \
		$(shell find data/raw/olist_order_payments -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_order_reviews \
		$(shell find data/raw/olist_order_reviews -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_geolocation \
		$(shell find data/raw/olist_geolocation -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_products \
		$(shell find data/raw/olist_products -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.olist_sellers \
		$(shell find data/raw/olist_sellers -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_localidades \
		$(shell find data/raw/ibge_localidades -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_censo_9936 \
		$(shell find data/raw/ibge_censo_9936 -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_censo_10295 \
		$(shell find data/raw/ibge_censo_10295 -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.ibge_censo_9514 \
		$(shell find data/raw/ibge_censo_9514 -name "*.parquet")
	bq load --replace --autodetect --source_format=PARQUET landing.bcb_pix \
		$(shell find data/raw/bcb_pix -name "*.parquet")
```

**`--replace`**: garante idempotência — re-executar `make bq-load` recria as tabelas sem acumular linhas.

**Verificação pós-carga obrigatória para IBGE:**
```bash
bq show landing.ibge_localidades
```
Confirmar que `microrregiao_id` e `mesorregiao_id` foram inferidos como `FLOAT64` (aceitável — staging faz cast para `INT64`).

---

### Passo 5 — Atualizar `dbt/profiles.yml`

Substituir conteúdo completo:

```yaml
geo_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: data-pipeline-lab-497514
      dataset: landing   # placeholder obrigatório pelo adapter — sobrescrito por generate_schema_name.sql
      location: US
      threads: 4
      timeout_seconds: 300
```

Validar:
```bash
cd dbt && uv run dbt debug --profiles-dir .
```

---

### Passo 6 — Atualizar `dbt/models/raw/_sources.yml`

A source aponta para o dataset `landing` (tabelas físicas do `bq load`).
O dataset `raw` continua sendo gerenciado pelo dbt como camada de views.

Substituir conteúdo completo:

```yaml
version: 2

sources:
  - name: landing
    database: data-pipeline-lab-497514
    schema: landing
    tables:
      - name: olist_customers
      - name: olist_orders
      - name: olist_order_items
      - name: olist_order_payments
      - name: olist_order_reviews
      - name: olist_geolocation
      - name: olist_products
      - name: olist_sellers
      - name: ibge_localidades
      - name: ibge_censo_9936
      - name: ibge_censo_10295
      - name: ibge_censo_9514
      - name: bcb_pix
```

### Passo 6b — Atualizar referências nos modelos raw

Todos os 13 arquivos em `dbt/models/raw/*.sql` referenciam `source('parquet_files', ...)` (estado da fase 4a).
Substituir globalmente:

```
source('parquet_files', → source('landing',
```

---

### Passo 7 — Criar macros cross-db

**`dbt/macros/compat_datediff.sql`** (novo arquivo):

```sql
{% macro compat_datediff(datepart, start, end) %}
    {% if target.type == 'bigquery' %}
        DATE_DIFF(DATE({{ end }}), DATE({{ start }}), {{ datepart }})
    {% else %}
        datediff('{{ datepart }}', {{ start }}, {{ end }})
    {% endif %}
{% endmacro %}
```

> Atenção: BigQuery inverte a ordem dos argumentos — `DATE_DIFF(end, start, part)`.
> Um erro aqui retorna valores negativos sem sinalizar erro.

**`dbt/macros/compat_mode.sql`** (novo arquivo):

```sql
{% macro compat_mode(expr) %}
    {% if target.type == 'bigquery' %}
        APPROX_TOP_COUNT({{ expr }}, 1)[OFFSET(0)].value
    {% else %}
        mode({{ expr }})
    {% endif %}
{% endmacro %}
```

**`dbt/macros/normalize_city_name.sql`** (atualizar arquivo existente):

```sql
{% macro normalize_city_name(column) %}
    {% if target.type == 'bigquery' %}
        regexp_replace(
          regexp_replace(regexp_replace(regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(
            lower({{ column }}),
            '[áàãâä]', 'a'),
            '[éèêë]', 'e'),
            '[íìîï]', 'i'),
            '[óòõôö]', 'o'),
            '[úùûü]', 'u'),
            '[ç]', 'c'),
          r'[ \-]', '_')
    {% else %}
        regexp_replace(
          regexp_replace(regexp_replace(regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(
            lower({{ column }}),
            '[áàãâä]', 'a', 'g'),
            '[éèêë]', 'e', 'g'),
            '[íìîï]', 'i', 'g'),
            '[óòõôö]', 'o', 'g'),
            '[úùûü]', 'u', 'g'),
            '[ç]', 'c', 'g'),
          '[ \-]', '_', 'g')
    {% endif %}
{% endmacro %}
```

> BigQuery's `REGEXP_REPLACE` substitui todas as ocorrências por padrão — o flag `'g'` não existe e causaria erro. DuckDB exige o flag para substituição global.
> Afeta 4 modelos intermediate: `int_ibge_municipios`, `int_olist_geolocation`, `int_dim_customers`, `int_dim_sellers`.

---

### Passo 8 — Corrigir débitos de dialeto — Staging

#### `TRY_CAST` → `SAFE_CAST` (7 modelos)

BigQuery não tem `TRY_CAST`. Substituição direta em todos os staging models:

| DuckDB | BigQuery |
|---|---|
| `try_cast(x as integer)` | `SAFE_CAST(x AS INT64)` |
| `try_cast(x as bigint)` | `SAFE_CAST(x AS INT64)` |
| `try_cast(x as double)` | `SAFE_CAST(x AS FLOAT64)` |
| `try_cast(x as timestamp)` | `SAFE_CAST(x AS TIMESTAMP)` |

Modelos afetados e contagem:

| Modelo | Ocorrências |
|---|---|
| `stg_olist_orders.sql` | 5 |
| `stg_olist_order_reviews.sql` | 2 |
| `stg_olist_order_items.sql` | 1 |
| `stg_ibge_localidades.sql` | 2 |
| `stg_ibge_censo_9936.sql` | 3 |
| `stg_ibge_censo_10295.sql` | 3 |
| `stg_ibge_censo_9514.sql` | 3 |

#### Operador `::cast` → `CAST(x AS TYPE)` (7 staging + 1 intermediate)

BigQuery não suporta o operador `::` de PostgreSQL/DuckDB. Aparece em dois contextos:

**No `row_hash` (coalesce):**
```sql
-- antes
coalesce(order_item_id::varchar, '')
-- depois
coalesce(CAST(order_item_id AS STRING), '')
```

**Em surrogate keys:**
```sql
-- antes
order_id || '-' || order_item_id::varchar
-- depois
order_id || '-' || CAST(order_item_id AS STRING)
```

Mapeamento de tipos:

| DuckDB | BigQuery |
|---|---|
| `::varchar` | `CAST(x AS STRING)` |
| `::integer` | `CAST(x AS INT64)` |
| `::bigint` | `CAST(x AS INT64)` |
| `::double` | `CAST(x AS FLOAT64)` |
| `::date` | `CAST(x AS DATE)` |

Modelos afetados: `stg_ibge_localidades`, `stg_bcb_pix`, `stg_olist_order_items`, `stg_olist_order_payments`, `stg_olist_products`, `stg_olist_geolocation`, `stg_olist_order_reviews`, `int_bcb_pix_municipio` (já coberto no Passo 8 — a substituição de `strptime` elimina o `::varchar` da mesma linha).

---

### Passo 9 — Corrigir débitos de dialeto — Intermediate

#### `dbt/models/intermediate/int_fact_orders.sql` — 3 ocorrências

```sql
-- antes
datediff('day', o.order_purchase_timestamp, o.order_approved_at)             as approval_days,
datediff('day', o.order_purchase_timestamp, o.order_estimated_delivery_date)  as estimated_delivery_days,
datediff('day', o.order_purchase_timestamp, o.order_delivered_customer_date)  as delivery_days,

-- depois
{{ compat_datediff('DAY', 'o.order_purchase_timestamp', 'o.order_approved_at') }}            as approval_days,
{{ compat_datediff('DAY', 'o.order_purchase_timestamp', 'o.order_estimated_delivery_date') }} as estimated_delivery_days,
{{ compat_datediff('DAY', 'o.order_purchase_timestamp', 'o.order_delivered_customer_date') }} as delivery_days,
```

#### `dbt/models/intermediate/int_olist_geolocation.sql` — 2 ocorrências

```sql
-- antes
mode(geolocation_city)   as geolocation_city,
mode(geolocation_state)  as geolocation_state

-- depois
{{ compat_mode('geolocation_city') }}   as geolocation_city,
{{ compat_mode('geolocation_state') }}  as geolocation_state
```

#### `dbt/models/intermediate/int_dim_customers.sql` — 3 ocorrências

```sql
-- antes
mode(customer_zip_code_prefix)  as customer_zip_code_prefix,
mode(customer_state)            as customer_state,
mode(customer_city)             as customer_city

-- depois
{{ compat_mode('customer_zip_code_prefix') }}  as customer_zip_code_prefix,
{{ compat_mode('customer_state') }}            as customer_state,
{{ compat_mode('customer_city') }}             as customer_city
```

#### `dbt/models/intermediate/int_olist_order_items_agg.sql` — 1 ocorrência

```sql
-- antes
mode(product_category_name)  as dominant_category_name

-- depois
{{ compat_mode('product_category_name') }}  as dominant_category_name
```

#### `dbt/models/intermediate/int_olist_order_payments_agg.sql` — 6 ocorrências

BigQuery não suporta `FILTER (WHERE ...)` — substituição direta no modelo, sem macro:

```sql
-- antes
sum(payment_value) filter (where payment_type = 'credit_card')        as credit_card_value,
max(payment_installments) filter (where payment_type = 'credit_card') as credit_card_installments,
sum(payment_value) filter (where payment_type = 'boleto')             as boleto_value,
sum(payment_value) filter (where payment_type = 'voucher')            as voucher_value,
sum(payment_value) filter (where payment_type = 'debit_card')         as debit_card_value,
sum(payment_value) filter (where payment_type = 'not_defined')        as not_defined_value,

-- depois
sum(if(payment_type = 'credit_card', payment_value, null))        as credit_card_value,
max(if(payment_type = 'credit_card', payment_installments, null)) as credit_card_installments,
sum(if(payment_type = 'boleto', payment_value, null))             as boleto_value,
sum(if(payment_type = 'voucher', payment_value, null))            as voucher_value,
sum(if(payment_type = 'debit_card', payment_value, null))         as debit_card_value,
sum(if(payment_type = 'not_defined', payment_value, null))        as not_defined_value,
```

#### `dbt/models/intermediate/int_bcb_pix_municipio.sql` — 1 ocorrência

```sql
-- antes
strptime(ano_mes::varchar, '%Y%m')::date  as ano_mes_data,

-- depois
PARSE_DATE('%Y%m', CAST(ano_mes AS STRING))  as ano_mes_data,
```

---

### Passo 10 — Validação incremental

Estratégia: validar modelo a modelo para controlar custo de queries.
**Não rodar `dbt build` completo a cada iteração.**

```bash
cd dbt

# 1. Verificar conexão
uv run dbt debug --profiles-dir .

# 2. Raw layer — valida bq load e sources
uv run dbt build --select raw --profiles-dir .

# 3. Staging — valida TRY_CAST→SAFE_CAST e ::cast→CAST
uv run dbt build --select staging --profiles-dir .

# 4. Modelos corrigidos — um a um
uv run dbt build --select int_fact_orders --profiles-dir .
uv run dbt build --select int_olist_geolocation --profiles-dir .
uv run dbt build --select int_dim_customers --profiles-dir .
uv run dbt build --select int_olist_order_items_agg --profiles-dir .
uv run dbt build --select int_olist_order_payments_agg --profiles-dir .
uv run dbt build --select int_bcb_pix_municipio --profiles-dir .

# 5. Intermediate restante
uv run dbt build --select intermediate --profiles-dir .

# 6. Marts
uv run dbt build --select marts --profiles-dir .

# 7. Build e test completo final
uv run dbt build --profiles-dir .
```

---

### Passo 11 — Migrar Streamlit

**Variáveis de ambiente necessárias** (adicionar ao `.env` ou exportar):

```
GCP_PROJECT=data-pipeline-lab-497514
GCP_DATASET_MARTS=marts
```

**`streamlit/app.py`** — substituir import e função de carga:

```python
# remover
import duckdb

# adicionar
from google.cloud import bigquery

# substituir load_data()
@st.cache_data(ttl=3600)
def load_data() -> pd.DataFrame:
    project = os.environ["GCP_PROJECT"]
    dataset = os.environ["GCP_DATASET_MARTS"]
    client = bigquery.Client(project=project)
    sql = f"SELECT * FROM `{project}.{dataset}.mart_geo_analytics`"
    return client.query(sql).to_dataframe()
```

> `@st.cache_data(ttl=3600)` obrigatório — evita query a cada re-render do Streamlit.

---

## Critério de conclusão

- `dbt build` completo sem erros ou falhas de teste
- `make streamlit` carrega dados do BigQuery sem erro
- Contagens de staging no BigQuery batem com os volumes conhecidos dos Parquets (fonte de verdade — não marts, que são derivados e podem mascarar erros de carga):

```bash
bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.staging.stg_olist_orders`'
# Esperado: 99.441

bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.staging.stg_bcb_pix`'
# Esperado: ~378.663 (após dedup técnica)

bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.staging.stg_ibge_localidades`'
# Esperado: 5.571
```

> Volumes de referência em `docs/understanding/fase_4b.md` — seção 5.

---

*Spec fechada em: Junho/2026*
