# Setup dbt-duckdb — Fase 4a Local

Passos para configurar o dbt com adaptador DuckDB para rodar localmente contra os Parquets em `data/raw/`.

---

## 1. Instalar dbt-duckdb

```bash
uv add dbt-duckdb
```

Versões instaladas:
- dbt-core: 1.11.11
- dbt-duckdb: 1.10.1

---

## 2. Criar `dbt/dbt_project.yml`

```yaml
name: 'geo_analytics'
version: '1.0.0'
config-version: 2

profile: 'geo_analytics'

model-paths: ["models"]
test-paths: ["tests"]
macro-paths: ["macros"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  geo_analytics:
    staging:
      +materialized: view
    intermediate:
      +materialized: table
    marts:
      +materialized: table
```

---

## 3. Criar `dbt/profiles.yml`

```yaml
geo_analytics:
  target: local
  outputs:
    local:
      type: duckdb
      path: "geo_analytics.duckdb"
      threads: 4
```

> `profiles.yml` não é commitado — está no `.gitignore`. Use `dbt/profiles.yml.example` como template.
> O `path` é relativo ao diretório `dbt/` — onde os comandos dbt são executados.
> **Fase 4b:** quando migrar para BigQuery, o `profiles.yml` passará a referenciar `dbt-bigquery` com `keyfile` ou `oauth`. Continuará fora do git — a mesma regra se aplica.

---

## 4. Testar a conexão

```bash
cd dbt
uv run dbt debug --profiles-dir .
```

Output esperado: `All checks passed!`

---

## 5. Rodar dbt

Todos os comandos dbt devem ser executados a partir do diretório `dbt/` com `--profiles-dir .`:

```bash
cd dbt
uv run dbt run --profiles-dir .
uv run dbt test --profiles-dir .
uv run dbt compile --profiles-dir .
```

---

## 6. Arquivos ignorados pelo git

```
dbt/profiles.yml       # credenciais locais
dbt/geo_analytics.duckdb  # banco DuckDB gerado
dbt/target/            # artefatos compilados
dbt/logs/              # logs de execução
dbt/dbt_packages/      # dependências instaladas
```

---

## Como o dbt lê os Parquets locais

O dbt-duckdb lê Parquets via `sources.yml` com a sintaxe de external sources:

```yaml
sources:
  - name: raw
    tables:
      - name: olist_orders
        meta:
          external_location: "read_parquet('../data/raw/olist_orders/**/*.parquet')"
```

O path é relativo ao diretório `dbt/`. O `**` cobre a partição `year=/month=/day=/`.
