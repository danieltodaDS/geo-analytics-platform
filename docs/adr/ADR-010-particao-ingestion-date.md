# ADR-010: Partição Hive por `ingestion_date` e Leitura da Última Partição no Staging

**Status:** Aceito
**Data:** Junho/2026
**Impacta:** [ADR-003](ADR-003-parquet-raw-layer.md), [ADR-008](ADR-008-staging-quality-policy.md)

---

## Decisão

Substituir as três colunas de partição Hive (`year`, `month`, `day`) por uma única coluna `ingestion_date=YYYY-MM-DD` em todos os paths da raw layer. Modelos de staging de fontes re-ingeríveis (BCB PIX, IBGE) filtram pela partição mais recente:

```sql
where ingestion_date = (select max(ingestion_date) from {{ source('raw', '<tabela>') }})
```

Modelos Olist não recebem o filtro — fonte ingerida uma única vez.

---

## Contexto

O path atual (`year=X/month=X/day=X/data.parquet`) acumula uma partição por execução. As fontes re-ingeríveis da v1 — BCB PIX e IBGE — são snapshots cumulativos: cada ingestão republica o histórico completo da fonte. O Olist é estático (batch único, Kaggle) e não é re-ingerido; não há risco de duplicação. Ainda assim, seu path é migrado para `ingestion_date` por consistência — ter dois formatos de partição no mesmo bucket aumenta a carga cognitiva operacional e quebra a uniformidade das external tables. Múltiplas execuções de BCB PIX ou IBGE no mesmo mês criam partições distintas que a external table lê em conjunto, duplicando registros no staging.

O incidente que motivou esta ADR: `dbt build` falhou com `FAIL 5571 dbt_utils_unique_combination_of_columns_int_bcb_pix_municipio` após duas execuções do pipeline no mesmo mês, gerando 5.571 linhas duplicadas (uma por município).

Alternativas consideradas para resolver idempotência:

| Alternativa | Problema |
|---|---|
| Apagar partição anterior no script de ingestão | Janela de ausência de dado entre delete e write; risco de pipeline falhar nesse intervalo |
| Dedup por `row_hash` no staging | Funciona para linhas byte-a-byte idênticas, mas falha quando a fonte atualiza retroativamente um registro (row_hash diferente → duplicata semântica passa para intermediate) |
| Leitura apenas da última partição (esta decisão) | Sem deleção, sem janela de risco, histórico preservado, filtro sobre coluna de partição é eliminado pelo pruning do BigQuery |

---

## Justificativa

**Uma coluna de data em vez de três inteiros:**
- Elimina a necessidade de reconstruir a data via `CONCAT(year, '-', LPAD(month), '-', LPAD(day))` em queries
- O BigQuery aplica partition pruning diretamente sobre `ingestion_date = <valor>` — a query no staging não escaneia partições anteriores
- A external table declara uma única coluna de partição em vez de três

**Leitura da última partição no staging:**
- Staging permanece `materialized='table'` (full refresh) — sem mudança de estratégia de materialização
- Histórico completo de ingestões preservado no GCS para auditoria sem custo operacional
- Idempotência garantida: rodar `dbt build` N vezes produz o mesmo resultado enquanto o GCS não receber nova ingestão

**Dedup por `row_hash` permanece** (ADR-008 preservado em essência):
- Remove duplicatas técnicas byte-a-byte dentro da partição lida — ruído de infraestrutura que pode existir mesmo num único arquivo
- Não é mais o mecanismo principal de idempotência entre execuções, mas continua necessário como linha de defesa dentro da partição

---

## Consequências

**Scripts de ingestão (`ingestion/src/*.py`):**
- Path muda de `{base}/{fonte}/year={Y}/month={MM}/day={DD}/data.parquet` para `{base}/{fonte}/ingestion_date={YYYY-MM-DD}/data.parquet`
- Nenhuma lógica de deleção necessária

**`infra/setup_external_tables.sh`:**
- `WITH PARTITION COLUMNS` passa de `(year INT64, month INT64, day INT64)` para `(ingestion_date DATE)`
- `hive_partition_uri_prefix` mantém o mesmo padrão

**Modelos de staging:**
- Fontes re-ingeríveis (BCB PIX, IBGE): adicionar filtro `where ingestion_date = (select max(ingestion_date) from {{ source(...) }})` antes do `QUALIFY`
- Modelos Olist: **não recebem o filtro** — fonte ingerida uma única vez; o filtro seria redundante e introduziria um subquery desnecessário
- `row_hash` continua excluindo `ingestion_date` do cálculo em todos os modelos (coluna de partição, não de negócio)

**ADR-003 — impacto:**
- A estrutura do path muda; o formato (Parquet + Snappy + Hive-style) permanece inalterado

**ADR-008 — impacto:**
- O papel do `row_hash` como "mecanismo de idempotência em cargas incrementais" é redefinido: passa a ser defesa técnica dentro da partição, não mecanismo entre execuções
- A coluna de partição descartada no hash passa de `year, month, day` para `ingestion_date`

**Fase local (dbt-duckdb) — fora do escopo:**
- A fase local com dbt-duckdb (ADR-007) não está operacional na versão atual do projeto — o adapter foi migrado para dbt-bigquery. Esta ADR cobre apenas a fase remota (BigQuery + GCS).
- Para retornar à arquitetura local com duckdb, utilizar a tag git `v0.1-fase-4a` que marca o último commit compatível com essa fase.

**Dados existentes no GCS:**
- Os dados atuais no path `year=X/month=X/day=X` devem ser apagados manualmente (`gsutil rm -r gs://{bucket}/raw/`) após a correção dos scripts de ingestão e antes da próxima execução do pipeline. A nova ingestão gravará no formato `ingestion_date=YYYY-MM-DD` e as external tables serão recriadas pelo `setup_external_tables.sh`.

**Brecha de resiliência documentada:**
- Se a última ingestão produziu arquivo corrompido ou incompleto, `max(ingestion_date)` aponta para ele e o staging lê dado inválido sem erro explícito. Com o modelo anterior (todas as partições lidas), uma partição corrompida seria diluída pelo volume das demais. Esta regressão de resiliência é aceita: o cenário é improvável dado o volume pequeno das fontes e a validação de volume mínimo já existente nos scripts de ingestão (`_VOLUME_MINIMO`).

---

*ADR criada em: Junho/2026*
