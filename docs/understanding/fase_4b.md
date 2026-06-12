# Understanding — Fase 4b: Migração dbt-duckdb → dbt-bigquery

> Resultado da exploração em `exploration/fase_4b_exploration.ipynb`.
> Base para a spec em `specs/dbt/fase_4b.md`.

---

## 1. Escopo da fase 4b

**O que muda:**
- Adapter dbt: `dbt-duckdb` → `dbt-bigquery`
- `profiles.yml`: apontar para BigQuery com autenticação OAuth (ADC)
- `sources.yml`: apontar para tabelas BigQuery (carregadas via `bq load`)
- Modelos dbt: correção de 4 débitos de dialeto SQL
- Streamlit: substituir DuckDB por `google-cloud-bigquery`

**O que NÃO muda:**
- Parquets em `data/raw/` — permanecem locais (GCS é fase 4c)
- Lógica de negócio de todos os modelos dbt
- Estrutura de camadas: raw → staging → intermediate → marts
- Suite de testes existente (`_staging.yml`, `_intermediate.yml`, `_marts.yml`)

---

## 2. Infraestrutura GCP

| Item | Valor |
|---|---|
| Projeto GCP | `data-pipeline-lab-497514` |
| gcloud SDK | 572.0.0 |
| bq CLI | 2.1.32 |
| Location datasets | `US` |

### Datasets criados (one-time via gcloud)

| Dataset | Camada dbt |
|---|---|
| `dev_raw` | raw |
| `dev_staging` | staging |
| `dev_intermediate` | intermediate |
| `dev_marts` | marts |

> Provisionamento one-time manual via `make setup-gcloud` — sem Terraform (fora do escopo v1, per ADR-009).

---

## 3. Autenticação

| Contexto | Mecanismo |
|---|---|
| dbt local | Application Default Credentials (ADC) via `gcloud auth application-default login` |
| Streamlit local | Mesmas ADC — sem `GOOGLE_APPLICATION_CREDENTIALS` explícito |
| CI/CD (fase 4c) | Workload Identity Federation (sem SA key — repo público, per ADR-009) |

> `profiles.yml` usa `method: oauth` — consome ADC automaticamente. Sem service account key em nenhum ambiente local.

---

## 4. Débitos de dialeto — inventário completo

Funções DuckDB sem equivalente direto no BigQuery:

| Função DuckDB | Modelos afetados | Equivalente BigQuery | Risco |
|---|---|---|---|
| `datediff('day', start, end)` | `int_fact_orders` | `DATE_DIFF(end, start, DAY)` — **ordem dos args invertida** | ALTO — silencioso (retorna negativo sem erro) |
| `mode(expr)` | `int_olist_geolocation`, `int_dim_customers`, `int_olist_order_items_agg` | `APPROX_TOP_COUNT(expr, 1)[OFFSET(0)].value` | ALTO — quebra com erro claro |
| `strptime(col, '%Y%m')` | `int_bcb_pix_municipio` | `PARSE_DATE('%Y%m', col)` | MÉDIO — quebra com erro claro |
| `FILTER (WHERE ...)` | `int_olist_order_payments_agg` | `IF(cond, expr, NULL)` dentro do agregado | MÉDIO — BigQuery **não suporta** `FILTER`, substituir diretamente no modelo |

### Estratégia: macros dbt cross-db

`dbt_utils 1.3.3` não fornece macro de `datediff` cross-db (verificado: só `date_spine.sql`). Criar macros próprias em `dbt/macros/`:

```sql
-- macros/compat_datediff.sql
{% macro compat_datediff(datepart, start, end) %}
    {% if target.type == 'bigquery' %}
        DATE_DIFF({{ end }}, {{ start }}, {{ datepart }})
    {% else %}
        datediff('{{ datepart }}', {{ start }}, {{ end }})
    {% endif %}
{% endmacro %}

-- macros/compat_mode.sql
{% macro compat_mode(expr) %}
    {% if target.type == 'bigquery' %}
        APPROX_TOP_COUNT({{ expr }}, 1)[OFFSET(0)].value
    {% else %}
        mode({{ expr }})
    {% endif %}
{% endmacro %}
```

> `strptime` e `FILTER` substituídos diretamente nos modelos (sem macro — sintaxe simples e não reutilizada).

---

## 5. Parquets locais — inventário para bq load

| Fonte | Tamanho | Linhas (aprox.) |
|---|---|---|
| `bcb_pix` | 23.373 KB | 378.663 |
| `ibge_censo_10295` | 260 KB | — |
| `ibge_censo_9514` | 173 KB | — |
| `ibge_censo_9936` | 130 KB | — |
| `ibge_localidades` | 168 KB | 5.571 |
| `olist_customers` | 6.839 KB | 96.096 |
| `olist_geolocation` | 16.620 KB | — |
| `olist_order_items` | 6.393 KB | — |
| `olist_order_payments` | 3.743 KB | — |
| `olist_order_reviews` | 9.383 KB | — |
| `olist_orders` | 10.525 KB | 99.441 |
| `olist_products` | 1.377 KB | — |
| `olist_sellers` | 131 KB | 3.095 |

**Total: ~80 MB** — bem dentro do free tier de storage do BigQuery (10 GB/mês).

### Mapeamento de tipos DuckDB → BigQuery

| DuckDB | BigQuery |
|---|---|
| `VARCHAR` | `STRING` |
| `BIGINT` | `INT64` |
| `DOUBLE` | `FLOAT64` |
| `BOOLEAN` | `BOOL` |

### Decisão: autodetect vs schema declarado

Usar `--autodetect` na carga inicial. Colunas de risco concreto (tipo inferido errado):

| Tabela | Coluna | Tipo no Parquet | Risco de inferência | Impacto |
|---|---|---|---|---|
| `ibge_localidades` | `microrregiao_id`, `mesorregiao_id` | `DOUBLE` | Inferido como `FLOAT64` | Aceitável — staging faz cast para `INT64` |
| `ibge_localidades` | `microrregiao_id`, `mesorregiao_id` | `DOUBLE` (nullable) | NULLs preservados | OK |
| todas | `year` | `BIGINT` | Inferido como `INT64` | OK |
| todas | `month`, `day` | `VARCHAR` | Inferido como `STRING` | OK |

Verificar schema real após carga via `bq show dev_raw.<tabela>` para as tabelas IBGE. Demais tabelas sem risco de inferência crítica.

> Não configurar particionamento BigQuery na fase 4b — escopo mínimo. Colunas `year`/`month`/`day` permanecem como colunas simples.

---

## 6. profiles.yml — estrutura fase 4b

```yaml
geo_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: data-pipeline-lab-497514
      dataset: dataset_dev   # valor de fallback — nunca usado na prática
      location: US
      threads: 4
      timeout_seconds: 300
```

> O campo `dataset` é obrigatório no profiles.yml do dbt-bigquery, mas **nunca é usado na prática**: a macro `generate_schema_name.sql` existente sobrescreve o schema de cada camada explicitamente (`dev_raw`, `dev_staging`, `dev_intermediate`, `dev_marts`). O valor `dataset_dev` serve apenas de placeholder para satisfazer a validação do adapter.

---

## 7. sources.yml — o que muda

O `_sources.yml` atual usa o mecanismo de `external_location` do dbt-duckdb para ler Parquets diretamente:

```yaml
# fase 4a (dbt-duckdb)
sources:
  - name: parquet_files
    tables:
      - name: olist_customers
        meta:
          external_location: "read_parquet('../data/raw/olist_customers/**/*.parquet')"
```

Na fase 4b, o source aponta para tabelas já carregadas no BigQuery via `bq load`:

```yaml
# fase 4b (dbt-bigquery)
sources:
  - name: raw
    database: data-pipeline-lab-497514
    schema: dev_raw
    tables:
      - name: olist_customers
      # ... demais tabelas
```

**Mudanças concretas:**
- `name: parquet_files` → `name: raw`
- `meta.external_location` removido de todas as tabelas
- `database` e `schema` adicionados no nível do source
- Os modelos raw que referenciam `{{ source('parquet_files', 'tabela') }}` passam a usar `{{ source('raw', 'tabela') }}`

---

## 8. Streamlit — conector

**Decisão: `google-cloud-bigquery` (Opção A)**

```python
from google.cloud import bigquery

@st.cache_data(ttl=3600)
def load_data() -> pd.DataFrame:
    project = os.environ["GCP_PROJECT"]
    dataset = os.environ["GCP_DATASET_MARTS"]
    client = bigquery.Client(project=project)
    sql = f"SELECT * FROM `{project}.{dataset}.mart_geo_analytics`"
    return client.query(sql).to_dataframe()
```

- Conector oficial, suporte nativo a ADC
- `@st.cache_data(ttl=3600)` reduz custo de queries repetidas
- `GCP_PROJECT` via variável de ambiente (não hardcoded)
- `google-cloud-bigquery` não está instalado — adicionar via `uv add`

> Streamlit 1.58.0 suporta `st.connection('bigquery')`, mas adiciona dependência de `sqlalchemy-bigquery`. Opção A é mais direta.

---

## 9. Custo estimado BigQuery

| Recurso | Free tier | Estimado fase 4b |
|---|---|---|
| Storage | 10 GB/mês | < 200 MB |
| Queries | 1 TB/mês | < 1 GB (marts pequenos) |

---

## 10. Sequência de implementação

| Passo | Ação |
|---|---|
| 1 | `git tag v0.1-fase-4a` |
| 2 | `uv remove dbt-duckdb` + `uv add dbt-bigquery` + `uv add google-cloud-bigquery` |
| 3 | Carregar Parquets → BigQuery via `bq load` (script ou Makefile) |
| 4 | Atualizar `profiles.yml` e `_sources.yml` |
| 5 | Criar macros `compat_datediff` e `compat_mode` |
| 6 | Corrigir modelos afetados pelos 4 débitos de dialeto |
| 7 | `dbt debug` + `dbt build --select <modelo>` por modelo afetado — não rodar build completo a cada iteração para controlar custo |
| 8 | `dbt build` completo + `dbt test` final |
| 9 | Migrar Streamlit para `google-cloud-bigquery` |
