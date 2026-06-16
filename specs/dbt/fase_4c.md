# Spec — Fase 4c: Remoto (GCS + External Tables + GitHub Actions)

> Pré-requisito: `docs/understanding/fase_4c.md` lido na íntegra.
> Base normativa: ADR-009, `conventions.md`, `data_quality.md`.
> Antes de gerar código, leia esta spec na íntegra.

---

## Contrato da fase

```
O que muda:     Repositório GitHub público criado (danieltodaDS/geo-analytics-platform)
                GCS bucket criado (geo-analytics-platform-raw)
                WIF + SA github-actions provisionados (ADR-009)
                Olist Parquets copiados para GCS (one-time gsutil cp)
                13 External Tables no dataset raw (substituem landing + raw views)
                Dataset landing eliminado
                13 arquivos models/raw/*.sql eliminados
                _sources.yml: source: landing → source: raw
                13 staging models: ref('table') → source('raw', 'table')
                ibge_localidades.py, ibge_censo.py, bcb_pix.py: escrita via gcsfs
                profiles.yml: dataset: landing → dataset: raw
                .github/workflows/ci.yml criado (pytest + dbt parse)
                .github/workflows/ingest.yml criado (workflow_dispatch — só escrita no GCS)
                .github/workflows/transform.yml criado (workflow_dispatch — dbt build)
                SA streamlit-reader criada (somente leitura)
                streamlit/app.py: ADC → credenciais via st.secrets

O que NÃO muda: Lógica SQL de todos os modelos staging/intermediate/marts
                Suite de testes completa (186 testes)
                Macros cross-db (compat_datediff, compat_mode, normalize_city_name)
                olist.py — sem alteração (Kaggle → filesystem local → gsutil cp one-time)
```

---

## Pré-requisitos

- Fase 4b concluída: 186 testes passando, Streamlit OK contra BigQuery
- ADC autenticada localmente: `make auth`
- Datasets `raw`, `staging`, `intermediate`, `marts` existindo no BigQuery
- `gcloud`, `gsutil`, `bq` instalados e configurados para `data-pipeline-lab-497514`

---

## Sequência de implementação

### Passo 0 — Criar repositório GitHub e configurar remote

```bash
gh repo create geo-analytics-platform \
  --public \
  --source=. \
  --remote=origin \
  --description="Pipeline de Analytics Engineering para Geo Analytics usando dados públicos brasileiros no GCP"

git push -u origin <branch-atual>
```

> `workflow_dispatch` só é acionável (via UI ou `gh` CLI) quando o arquivo do workflow existe no branch **padrão (main)**. Merge em main é obrigatório antes de testar workflows remotamente.

---

### Passo 1 — Branch e tag

```bash
git checkout -b feat/fase-4c-remoto
git tag v0.2-fase-4b
```

---

### Passo 2 — Provisionamento GCP (one-time)

Executar sequencialmente — cada passo depende do anterior.

#### 2a. Habilitar APIs necessárias

```bash
gcloud services enable iamcredentials.googleapis.com \
  --project=data-pipeline-lab-497514
```

Necessário para WIF — sem esta API o token OAuth2 da SA não é gerado e a escrita no GCS falha com `PERMISSION_DENIED`.

#### 2b. Criar bucket GCS

```bash
gcloud storage buckets create gs://geo-analytics-platform-raw \
  --location=US \
  --uniform-bucket-level-access
```

#### 2c. Criar WIF pool e provider

```bash
# Pool
gcloud iam workload-identity-pools create github-actions \
  --location=global \
  --project=data-pipeline-lab-497514 \
  --display-name="GitHub Actions"

# OIDC Provider
gcloud iam workload-identity-pools providers create-oidc github \
  --location=global \
  --workload-identity-pool=github-actions \
  --project=data-pipeline-lab-497514 \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='danieltodaDS/geo-analytics-platform'"
```

#### 2d. Criar SA de ingestão e vincular ao WIF

```bash
# Service account
gcloud iam service-accounts create github-actions \
  --project=data-pipeline-lab-497514 \
  --display-name="GitHub Actions"

# Binding: repo pode impersonar a SA
gcloud iam service-accounts add-iam-policy-binding \
  github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com \
  --project=data-pipeline-lab-497514 \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/549617161512/locations/global/workloadIdentityPools/github-actions/attribute.repository/danieltodaDS/geo-analytics-platform"
```

#### 2e. IAM da SA de ingestão

```bash
# GCS — escrever Parquets
gcloud storage buckets add-iam-policy-binding gs://geo-analytics-platform-raw \
  --role=roles/storage.objectUser \
  --member=serviceAccount:github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com

# BigQuery — criar/substituir tabelas e views (project-level)
gcloud projects add-iam-policy-binding data-pipeline-lab-497514 \
  --role=roles/bigquery.dataEditor \
  --member=serviceAccount:github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com

# BigQuery — executar jobs (dbt + bq)
gcloud projects add-iam-policy-binding data-pipeline-lab-497514 \
  --role=roles/bigquery.jobUser \
  --member=serviceAccount:github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com
```

---

### Passo 3 — Upload Olist → GCS (one-time)

Olist é estático e não tem script de ingestão remota — os Parquets locais são a fonte.

```bash
gsutil -m cp -r data/raw/olist_customers  gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_orders     gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_order_items     gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_order_payments  gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_order_reviews   gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_geolocation     gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_products        gs://geo-analytics-platform-raw/raw/
gsutil -m cp -r data/raw/olist_sellers         gs://geo-analytics-platform-raw/raw/
```

**Verificação:**
```bash
gsutil ls gs://geo-analytics-platform-raw/raw/olist_orders/
# Esperado: year=2016/, year=2017/, year=2018/
```

---

### Passo 4 — Criar External Tables no dataset `raw`

13 External Tables substituem os 13 dbt raw views + dataset `landing`. Criadas via DDL; o dbt não as gerencia.

Salvar como `infra/setup_external_tables.sh` e adicionar `make setup-external-tables` ao Makefile (`bash infra/setup_external_tables.sh`):

```bash
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
```

---

### Passo 5 — Drop `landing` e remover raw views dbt

#### 5a. Drop dataset `landing`

Confirmar volumes via External Tables antes de dropar:

```bash
bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.raw.olist_orders`'
# Esperado: 99.441 — só continuar após confirmar este valor

bq rm -r -f data-pipeline-lab-497514:landing
```

#### 5b. Remover `models/raw/*.sql`

```bash
rm dbt/models/raw/*.sql
```

Os 13 arquivos em `models/raw/` (ex: `olist_customers.sql`, `bcb_pix.sql`) são eliminados. As External Tables do dataset `raw` os substituem diretamente.

#### 5c. Atualizar `dbt/profiles.yml` — placeholder

```yaml
geo_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: data-pipeline-lab-497514
      dataset: raw   # placeholder — sobrescrito por generate_schema_name.sql
      location: US
      threads: 4
      timeout_seconds: 300
```

---

### Passo 6 — Atualizar `_sources.yml` e staging

#### 6a. Substituir `dbt/models/raw/_sources.yml`

```yaml
version: 2

sources:
  - name: raw
    database: data-pipeline-lab-497514
    schema: raw
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

#### 6b. Migrar 13 staging models: `ref()` → `source('raw', ...)`

Em cada `dbt/models/staging/stg_*.sql`, substituir a referência no `FROM`:

| Antes | Depois |
|---|---|
| `FROM {{ ref('olist_customers') }}` | `FROM {{ source('raw', 'olist_customers') }}` |
| `FROM {{ ref('olist_orders') }}` | `FROM {{ source('raw', 'olist_orders') }}` |
| `FROM {{ ref('olist_order_items') }}` | `FROM {{ source('raw', 'olist_order_items') }}` |
| `FROM {{ ref('olist_order_payments') }}` | `FROM {{ source('raw', 'olist_order_payments') }}` |
| `FROM {{ ref('olist_order_reviews') }}` | `FROM {{ source('raw', 'olist_order_reviews') }}` |
| `FROM {{ ref('olist_geolocation') }}` | `FROM {{ source('raw', 'olist_geolocation') }}` |
| `FROM {{ ref('olist_products') }}` | `FROM {{ source('raw', 'olist_products') }}` |
| `FROM {{ ref('olist_sellers') }}` | `FROM {{ source('raw', 'olist_sellers') }}` |
| `FROM {{ ref('ibge_localidades') }}` | `FROM {{ source('raw', 'ibge_localidades') }}` |
| `FROM {{ ref('ibge_censo_9514') }}` | `FROM {{ source('raw', 'ibge_censo_9514') }}` |
| `FROM {{ ref('ibge_censo_10295') }}` | `FROM {{ source('raw', 'ibge_censo_10295') }}` |
| `FROM {{ ref('ibge_censo_9936') }}` | `FROM {{ source('raw', 'ibge_censo_9936') }}` |
| `FROM {{ ref('bcb_pix') }}` | `FROM {{ source('raw', 'bcb_pix') }}` |

**Validação incremental após Passo 6:**
```bash
cd dbt
uv run dbt parse --profiles-dir .
uv run dbt build --select staging --profiles-dir .
# Esperado: 13 modelos + testes staging passando
```

---

### Passo 7 — Adicionar `gcsfs` e modificar scripts de ingestão

#### 7a. Adicionar dependência

```bash
uv add gcsfs
```

#### 7b. Padrão de modificação (idêntico nos 3 scripts)

`ibge_localidades.py`, `ibge_censo.py`, `bcb_pix.py` — substituir o bloco de escrita do Parquet:

```python
# antes
dest = Path(base) / "{fonte}" / f"year={today.year}" / f"month={today.month:02d}" / f"day={today.day:02d}" / "data.parquet"
dest.parent.mkdir(parents=True, exist_ok=True)
df.to_parquet(dest, index=False)

# depois
dest = f"{base}/{fonte}/year={today.year}/month={today.month:02d}/day={today.day:02d}/data.parquet"
if not dest.startswith("gs://"):
    Path(dest).parent.mkdir(parents=True, exist_ok=True)
df.to_parquet(dest, index=False)
```

`RAW_BASE_PATH` não definida → fallback `data/raw` — comportamento local inalterado.

`olist.py` não é modificado — Olist usa Kaggle → filesystem → gsutil cp (Passo 3).

**Política de re-execução — BCB PIX:** re-executar no mesmo dia sobrescreve o arquivo existente (mesmo path). Re-executar em dia diferente cria nova partição — a External Table enxerga ambas, resultando em linhas duplicadas no mart. Para refresh completo: apagar o prefix antes de executar (`gsutil rm -r gs://geo-analytics-platform-raw/raw/bcb_pix/`). Para v1, o ingest roda uma única vez — sem impacto prático.

---

### Passo 8 — Criar `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v5

      - run: uv sync

      - run: uv run pytest

      - name: dbt parse
        run: cd dbt && uv run dbt deps --profiles-dir . && uv run dbt parse --profiles-dir .
```

Sem bloco WIF — `dbt parse` valida YAML, Jinja, `ref()`/`source()` e macros sem conexão ao warehouse.

---

### Passo 9 — Criar `.github/workflows/ingest.yml`

```yaml
name: Ingest

on:
  workflow_dispatch:
    inputs:
      source:
        description: "Fonte a ingerir"
        required: true
        default: all
        type: choice
        options:
          - all
          - ibge_localidades
          - ibge_censo
          - bcb_pix

jobs:
  ingest:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v5

      - run: uv sync

      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/549617161512/locations/global/workloadIdentityPools/github-actions/providers/github
          service_account: github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com

      - name: Ingest
        env:
          RAW_BASE_PATH: gs://geo-analytics-platform-raw/raw
        run: |
          SOURCE="${{ github.event.inputs.source }}"
          if [ "$SOURCE" = "all" ] || [ "$SOURCE" = "ibge_localidades" ]; then
            uv run python ingestion/src/ibge_localidades.py
          fi
          if [ "$SOURCE" = "all" ] || [ "$SOURCE" = "ibge_censo" ]; then
            uv run python ingestion/src/ibge_censo.py
          fi
          if [ "$SOURCE" = "all" ] || [ "$SOURCE" = "bcb_pix" ]; then
            uv run python ingestion/src/bcb_pix.py
          fi
```

**Notas:**
- `id-token: write` é obrigatório para WIF — sem ele o OIDC token não é emitido.
- `dbt build` **não está neste workflow** — ingestão e transformação são responsabilidades distintas. `dbt build` está em `transform.yml` (Passo 9b).
- Olist não tem input: está em GCS desde o Passo 3 e as External Tables sempre refletem os arquivos existentes.

---

### Passo 9b — Criar `.github/workflows/transform.yml`

```yaml
name: Transform

on:
  workflow_dispatch:

jobs:
  transform:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v5

      - run: uv sync

      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/549617161512/locations/global/workloadIdentityPools/github-actions/providers/github
          service_account: github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com

      - name: dbt build
        run: cd dbt && uv run dbt deps --profiles-dir . && uv run dbt build --profiles-dir .
```

**Pré-condição de bootstrap:** as External Tables do dataset `raw` devem existir antes do primeiro run (Passo 4). Rodar `transform.yml` antes de `passo-4` resulta em `Not found: Table raw.<tabela>`.

---

### Passo 10 — SA Streamlit e `streamlit/app.py`

#### 10a. Criar SA `streamlit-reader`

```bash
gcloud iam service-accounts create streamlit-reader \
  --project=data-pipeline-lab-497514 \
  --display-name="Streamlit Reader"

# Somente leitura em marts
bq add-iam-policy-binding \
  --dataset=data-pipeline-lab-497514:marts \
  --role=roles/bigquery.dataViewer \
  --member=serviceAccount:streamlit-reader@data-pipeline-lab-497514.iam.gserviceaccount.com

# Executar jobs de leitura
gcloud projects add-iam-policy-binding data-pipeline-lab-497514 \
  --role=roles/bigquery.jobUser \
  --member=serviceAccount:streamlit-reader@data-pipeline-lab-497514.iam.gserviceaccount.com

# Gerar chave JSON
gcloud iam service-accounts keys create streamlit-key.json \
  --iam-account=streamlit-reader@data-pipeline-lab-497514.iam.gserviceaccount.com

# Copiar conteúdo para o clipboard (evita exposição no scrollback do terminal)
xclip -selection clipboard < streamlit-key.json
# Colar no painel do Streamlit Community Cloud: Secrets → gcp_service_account

# Deletar o arquivo local imediatamente após configurar o secret
rm streamlit-key.json
# Confirmar também no console GCP: IAM → Service Accounts → streamlit-reader → Keys
```

> `streamlit-key.json` nunca entra no repositório. Usar `xclip` em vez de `cat` evita que o conteúdo da chave fique exposto no scrollback buffer do terminal. A deleção local é obrigatória.

#### 10b. Atualizar `streamlit/app.py`

Substituir o bloco de criação do cliente BigQuery:

```python
# adicionar import
from google.oauth2 import service_account

# substituir dentro de load_data()
# antes
client = bigquery.Client(project=project)

# depois
credentials = service_account.Credentials.from_service_account_info(
    st.secrets["gcp_service_account"],
    scopes=["https://www.googleapis.com/auth/bigquery.readonly"],
)
client = bigquery.Client(project=project, credentials=credentials)
```

**Execução local:** `st.secrets` lê de `.streamlit/secrets.toml`. Verificar `.gitignore` antes de criar o arquivo:

```bash
grep -q '\.streamlit/secrets\.toml' .gitignore || echo '.streamlit/secrets.toml' >> .gitignore
```

Criar o arquivo:

```toml
[gcp_service_account]
type = "service_account"
project_id = "data-pipeline-lab-497514"
# ... restante do JSON da chave
```

---

### Passo 11 — Validação completa

#### dbt build completo

```bash
cd dbt
uv run dbt build --profiles-dir .
# Esperado: 186 testes passando
```

#### Volumes staging (fonte de verdade)

```bash
bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.staging.stg_olist_orders`'
# Esperado: 99.441

bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.staging.stg_bcb_pix`'
# Esperado: ~378.663

bq query --nouse_legacy_sql \
  'SELECT COUNT(*) FROM `data-pipeline-lab-497514.staging.stg_ibge_localidades`'
# Esperado: 5.571
```

#### CI — simular pipeline local

```bash
uv run pytest
cd dbt && uv run dbt deps --profiles-dir . && uv run dbt parse --profiles-dir .
# Esperado: sem erros (não requer autenticação BQ)
```

#### Bootstrap — primeira execução remota

`workflow_dispatch` só funciona para workflows presentes no branch padrão (main). Sequência obrigatória no primeiro run:

1. Merge da feature branch em main (PR)
2. Ingerir todas as fontes dinâmicas:
   ```bash
   gh workflow run ingest.yml --ref main --field source=ibge_localidades
   gh workflow run ingest.yml --ref main --field source=ibge_censo
   gh workflow run ingest.yml --ref main --field source=bcb_pix
   ```
3. Criar External Tables (passo-4) — pode rodar com dados parciais; BigQuery registra o DDL sem ler os arquivos
4. Acionar `transform.yml`:
   ```bash
   gh workflow run transform.yml --ref main
   ```
   Esperado: 186 testes passando

#### Streamlit Community Cloud

1. Conectar repo em share.streamlit.io
2. Configurar secret `gcp_service_account` com o conteúdo do `streamlit-key.json`
3. Verificar que o app carrega dados do dataset `marts`

---

## Critério de conclusão

- `uv run pytest` + `dbt parse` passam sem credenciais BQ (CI)
- `ingest.yml` executado com sucesso via `workflow_dispatch`: Parquets em GCS para todas as fontes dinâmicas
- `transform.yml` executado com sucesso via `workflow_dispatch`: 186 testes passando contra BigQuery
- Streamlit Community Cloud rodando contra `marts` com SA de somente leitura

---

*Spec criada em: Junho/2026*
