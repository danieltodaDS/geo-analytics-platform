# ADR-009: GitHub Actions para Ingestão Remota

**Status:** Aceito
**Data:** Junho/2026
**Supersede:** [ADR-002](ADR-002-cloud-run-scheduler.md)

---

## Decisão

Usar GitHub Actions (`workflow_dispatch`) para execução remota dos scripts de ingestão, eliminando Cloud Run Jobs e Cloud Scheduler.

## Contexto

A ADR-002 assumiu que os scripts de ingestão precisariam de agendamento confiável em produção. Essa premissa mudou: todas as fontes têm cargas pontuais e esporádicas.

| Fonte | Frequência real |
|---|---|
| Olist | Batch único — dataset histórico estático |
| IBGE Localidades | Raramente muda; refresh manual quando IBGE publica revisão |
| IBGE Censo 2022 | Uma vez por censo (~10 anos) |
| BCB PIX | Covariável estática para o experimento — sem necessidade de atualização contínua |

Com esse perfil de carga, o problema a resolver não é "agendamento confiável" — é "trigger manual confiável a partir de qualquer ambiente, sem dependência do local do desenvolvedor".

## Justificativa

`workflow_dispatch` resolve exatamente esse problema:
- Acionável via GitHub UI, CLI (`gh workflow run`) ou API — sem depender do ambiente local
- Os scripts já usam `uv`; um runner do GitHub Actions executa `uv sync && uv run python ingest.py` sem Docker, Artifact Registry ou IAM de Cloud Run
- Repositórios públicos têm minutos ilimitados no GitHub Actions — sem cota a monitorar
- Zero infraestrutura para provisionar: sem bucket de estado Terraform, sem service account de Cloud Run, sem regras de IAM de Jobs

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| Cloud Run + Cloud Scheduler (ADR-002) | Over-engineering para ~5 execuções totais; Artifact Registry + Terraform + IAM de Cloud Run desproporcional à frequência |
| Cloud Run sem scheduler (trigger manual) | Ainda exige Artifact Registry, build/push de imagem Docker, IAM de Jobs — overhead sem benefício para carga esporádica |
| Execução apenas local | Não resolve o requisito de full refresh sem depender do ambiente local |

## Consequências

- Terraform deixa de ser necessário para a v1 — BigQuery dataset e bucket GCS são provisionados uma única vez via `gcloud` (comandos documentados na spec da Feature 8)
- A fase "Remoto" do roadmap é reduzida: sem `deploy.yml` de build/push de imagem, apenas `ingest.yml` com `workflow_dispatch`
- O `ingest.yml` cobre o pipeline completo: `uv run python ingest.py` → Parquet em GCS → `bq load` no dataset raw do BigQuery
- dbt na fase remota roda via dbt-core em GitHub Actions (step `dbt run --target prod`) ou dbt Cloud — ambos válidos; dbt Cloud opcional para portfólio

### Autenticação GCP no runner

O runner precisa de credenciais para escrever no GCS e no BigQuery. Duas abordagens:

| Abordagem | Como funciona | Risco |
|---|---|---|
| **Workload Identity Federation (recomendado)** | Runner se autentica via OIDC; GCP emite token de curta duração. Sem segredo persistente armazenado no GitHub | Requer criação de pool de identidade e binding de service account no GCP |
| Service account JSON key | Chave JSON armazenada como secret no GitHub Actions | Segredo de longa duração — vazamento acidental em log ou PR expõe acesso ao projeto GCP |

**Decisão para a v1:** Workload Identity Federation. Repositório público de portfólio: o risco de uma service account key vazar em um log de workflow ou diff de PR é concreto. WIF elimina o segredo persistente; o custo de setup (pool + binding) é único e documentado na Feature 8.

```
Local                     Remoto
Makefile                  GitHub Actions (workflow_dispatch)
    ↓                         ↓
uv run python ingest.py   uv run python ingest.py
    ↓                         ↓
Parquet em data/raw/      Parquet em GCS
                              ↓
                          bq load → dataset_raw no BigQuery
```
