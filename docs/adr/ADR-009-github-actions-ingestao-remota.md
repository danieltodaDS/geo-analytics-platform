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
- Free tier do GitHub Actions (2.000 min/mês em repositórios públicos) cobre anos de execução esporádica
- Zero infraestrutura para provisionar: sem bucket de estado Terraform, sem service account de Cloud Run, sem regras de IAM de Jobs

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| Cloud Run + Cloud Scheduler (ADR-002) | Over-engineering para ~5 execuções totais; Artifact Registry + Terraform + IAM de Cloud Run desproporcional à frequência |
| Cloud Run sem scheduler (trigger manual) | Ainda exige Artifact Registry, build/push de imagem Docker, IAM de Jobs — overhead sem benefício para carga esporádica |
| Execução apenas local | Não resolve o requisito de full refresh sem depender do ambiente local |

## Consequências

- Terraform deixa de ser necessário para a v1 — sem infraestrutura GCP para versionar além do que o BigQuery e GCS já provisionam via console ou script único
- A fase "Remoto" do roadmap é reduzida: sem `deploy.yml` de build/push de imagem, apenas `ingest.yml` com `workflow_dispatch`
- dbt na fase remota roda via dbt-core em GitHub Actions (step `dbt run --target prod`) ou dbt Cloud — ambos válidos; dbt Cloud opcional para portfólio

```
Local                     Remoto
Makefile                  GitHub Actions (workflow_dispatch)
    ↓                         ↓
uv run python script.py   uv run python script.py
    ↓                         ↓
         mesmo script Python
         mesmo uv.lock
```
