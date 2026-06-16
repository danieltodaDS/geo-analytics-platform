# Entendimento — Fase 4c (Remoto)

> Decisões arquiteturais resolvidas antes da especificação da Feature 8.
> Acumulado incrementalmente durante o ciclo Entender.

---

## 1. GCS Bucket

**Bucket:** `geo-analytics-platform-raw`
**Região:** `US` (multi-region — mesma dos datasets BigQuery, sem egress cost)
**Status:** não existe ainda — criado como parte do provisionamento GCP (item 13 do roadmap)

**Estrutura de paths** (já definida em `docs/normative/conventions.md`):
```
gs://geo-analytics-platform-raw/raw/{fonte}/year=YYYY/month=MM/day=DD/data.parquet
```

**Comando de criação:**
```bash
gcloud storage buckets create gs://geo-analytics-platform-raw \
  --location=US \
  --uniform-bucket-level-access
```

**Relação com BigQuery:** na fase 4c não há `bq load`. O dataset `landing` passa a conter **External Tables** apontando para os paths GCS — criadas uma única vez no provisionamento (ver seção 5). Após o ingest escrever o Parquet no GCS, a External Table enxerga os novos dados automaticamente via scan do prefix.

**Variáveis de ambiente:**
- `GCS_BUCKET=geo-analytics-platform-raw` — usado em comandos de infra (criação do bucket, criação das External Tables, Makefile targets). Não é lido pelos scripts Python.
- `RAW_BASE_PATH=gs://geo-analytics-platform-raw/raw` — lido pelos scripts Python (seção 2). Já contém o bucket embutido; `GCS_BUCKET` evita duplicar o nome em contextos de infra.

---

## 2. RAW_BASE_PATH — como os scripts mudam de destino

**Abordagem:** `gcsfs` + paths como string (sem gsutil cp intermediário)

`pandas` com `gcsfs` instalado entende `gs://...` nativamente via `fsspec`. A autenticação herda do ADC configurado no runner — sem configuração extra.

**Nova dep:** `uv add gcsfs`

**Mudança nos scripts (padrão idêntico nos 3 scripts remotos):**

```python
# antes
dest = Path(base) / "fonte" / f"year={today.year}" / ...
dest.parent.mkdir(parents=True, exist_ok=True)
df.to_parquet(dest, ...)

# depois
dest = f"{base}/fonte/year={today.year}/..."
if not dest.startswith("gs://"):
    Path(dest).parent.mkdir(parents=True, exist_ok=True)
df.to_parquet(dest, ...)
```

**Escopo de mudança de código:** apenas `ibge_localidades.py`, `ibge_censo.py`, `bcb_pix.py`.

**Olist — write local + gsutil cp (adequado):**
`olist.py` depende de CSVs do Kaggle que chegam obrigatoriamente como arquivos locais. Não há como pular o filesystem — a entrada já é disco. Escrever o Parquet localmente e depois copiar para GCS é continuação natural desse fluxo, sem overhead adicional. Os Parquets precisam estar no GCS para que as External Tables do `landing` funcionem, mas chegam lá via upload one-time no provisionamento:
```bash
gsutil cp -r data/raw/olist_* gs://geo-analytics-platform-raw/raw/
```
Nenhuma mudança em `olist.py`. A assimetria com os outros scripts é intencional — cada fonte segue sua natureza.

**Variável de ambiente no runner:**
- `RAW_BASE_PATH=gs://geo-analytics-platform-raw/raw`
- `GCS_BUCKET=geo-analytics-platform-raw`

**Local (fases 4a/4b):** `RAW_BASE_PATH` não definida → fallback `data/raw` — comportamento inalterado.

---

## 3. Workload Identity Federation

**Nada existe ainda** — SA, pool e provider precisam ser criados.

### Recursos a criar

| Recurso | ID / Nome |
|---|---|
| Service Account | `github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com` |
| WIF Pool | `github-actions` (global) |
| WIF Provider (OIDC) | `github` |
| Repositório autorizado | `danieltodaDS/geo-analytics-platform` |
| Project Number | `549617161512` |

### Sequência de criação (5 passos)

```bash
# 1. Service account
gcloud iam service-accounts create github-actions \
  --project=data-pipeline-lab-497514 \
  --display-name="GitHub Actions"

# 2. WIF Pool
gcloud iam workload-identity-pools create github-actions \
  --location=global \
  --project=data-pipeline-lab-497514 \
  --display-name="GitHub Actions"

# 3. OIDC Provider (GitHub Actions como emissor)
gcloud iam workload-identity-pools providers create-oidc github \
  --location=global \
  --workload-identity-pool=github-actions \
  --project=data-pipeline-lab-497514 \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='danieltodaDS/geo-analytics-platform'"

# 4. Binding: permite que o repo impersone a SA
gcloud iam service-accounts add-iam-policy-binding \
  github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com \
  --project=data-pipeline-lab-497514 \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/549617161512/locations/global/workloadIdentityPools/github-actions/attribute.repository/danieltodaDS/geo-analytics-platform"

# 5. IAM: permissões da SA nos recursos do projeto
#    GCS — escrever e sobrescrever Parquets
gcloud storage buckets add-iam-policy-binding gs://geo-analytics-platform-raw \
  --role=roles/storage.objectUser \
  --member=serviceAccount:github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com

#    BigQuery — criar/substituir tabelas e views (bq load + dbt)
for ds in landing raw staging intermediate marts; do
  bq add-iam-policy-binding \
    --dataset=data-pipeline-lab-497514:${ds} \
    --role=roles/bigquery.dataEditor \
    --member=serviceAccount:github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com
done

#    BigQuery — executar jobs (dbt queries + bq load)
gcloud projects add-iam-policy-binding data-pipeline-lab-497514 \
  --role=roles/bigquery.jobUser \
  --member=serviceAccount:github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com
```

### Bloco de autenticação no workflow

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/549617161512/locations/global/workloadIdentityPools/github-actions/providers/github
    service_account: github-actions@data-pipeline-lab-497514.iam.gserviceaccount.com
```

Após esse step, `gcloud`, `gsutil`, `bq` e `gcsfs` herdam as credenciais via ADC — sem segredo persistente no GitHub.

---

## 4. ci.yml — escopo e target

**Decisão:** `pytest` + `dbt parse` — sem `dbt test`, sem WIF, sem credenciais BQ.

**Verificação empírica:** `dbt compile` com adapter dbt-bigquery tenta autenticar (`Failed to authenticate with supplied credentials`). `dbt parse` com as mesmas credenciais inválidas passa sem erro — valida YAML, Jinja, `ref()`/`source()` e macros sem abrir conexão ao warehouse. É suficiente para garantir que nenhum PR quebra a estrutura do projeto dbt.

**Sem bloco WIF no ci.yml** — simplificação mantida, decisão agora verificada.

**Steps do ci.yml:**
```
uv sync
uv run pytest
cd dbt && uv run dbt deps && uv run dbt parse --profiles-dir .
```

---

## 5. Streamlit 4c — destino de deploy

**Decisão:** Streamlit Community Cloud (grátis, repo público, sem infra).

**Autenticação ao BigQuery:** Streamlit Community Cloud não suporta WIF nem ADC. A autenticação usa SA JSON key armazenada como Streamlit secret (`st.secrets`). SA dedicada, somente leitura:
- `roles/bigquery.dataViewer` no dataset `marts`
- `roles/bigquery.jobUser` no projeto

SA separada da SA de ingestão (`github-actions`) — princípio do menor privilégio.

**Mudança de código necessária em `streamlit/app.py`:** o cliente BQ atual usa ADC implícito (`bigquery.Client(project=project)`). No Streamlit Cloud, ADC não está disponível — precisa passar credenciais explicitamente a partir de `st.secrets`:

```python
from google.oauth2 import service_account

credentials = service_account.Credentials.from_service_account_info(
    st.secrets["gcp_service_account"],
    scopes=["https://www.googleapis.com/auth/bigquery.readonly"],
)
client = bigquery.Client(project=project, credentials=credentials)
```

O secret `gcp_service_account` é configurado no painel do Streamlit Community Cloud — nunca entra no repositório.

---

## 6. External Tables — arquitetura e criação

### Arquitetura na fase 4c

Dataset `landing` é eliminado. Dataset `raw` passa a conter External Tables — criadas no provisionamento, fora do dbt. Os 13 dbt raw views (`models/raw/*.sql`) são eliminados.

```
GCS gs://geo-analytics-platform-raw/raw/{fonte}/year=YYYY/month=MM/day=DD/data.parquet
  → raw.{table}           (External Table — fora do dbt)
  → staging.stg_{table}   (dbt — ref() → source('raw', ...))
  → intermediate → marts
```

**Mudanças no dbt em relação à fase 4b:**

| Artefato | Fase 4b | Fase 4c |
|---|---|---|
| Dataset `landing` | Tabelas físicas (`bq load`) | Eliminado |
| `models/raw/*.sql` | 13 views sobre `landing` | Eliminados |
| `_sources.yml` | `source: landing` | `source: raw` |
| Staging (`ref`) | `{{ ref('olist_customers') }}` | `{{ source('raw', 'olist_customers') }}` |

Colunas de partição (`year`, `month`, `day`) ficam disponíveis nativamente em staging — sem exclusão, sem perda de informação.

### Criação das External Tables

BigQuery DDL via `bq query` — sem tooling adicional. Template:

```sql
CREATE OR REPLACE EXTERNAL TABLE `data-pipeline-lab-497514.raw.{table}`
WITH PARTITION COLUMNS (
  year  INT64,
  month INT64,
  day   INT64
)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://geo-analytics-platform-raw/raw/{fonte}/*/*/*.parquet'],
  hive_partition_uri_prefix = 'gs://geo-analytics-platform-raw/raw/{fonte}',
  require_hive_partition_filter = false
);
```

`require_hive_partition_filter = false` permite que staging leia sem filtro de partição obrigatório.

### Partições e re-execução do ingest

Cada execução escreve para `year=YYYY/month=MM/day=DD/` com a data de execução. Re-executar em dias diferentes cria partições distintas — External Table retorna a união de todas. Para fontes estáticas (Olist, IBGE) isso não é problema prático: o ingest roda uma única vez. Para BCB PIX, se houver refresh, a spec definirá a política (sobrescrever o mesmo path ou acumular).
