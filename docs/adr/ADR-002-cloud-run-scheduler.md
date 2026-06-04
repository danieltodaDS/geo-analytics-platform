# ADR-002: Cloud Run + Cloud Scheduler para Ingestão em Produção

**Status:** Aceito
**Data:** Junho/2026

---

## Decisão

Usar Cloud Run Jobs para execução dos scripts de ingestão e Cloud Scheduler para agendamento em produção.

## Contexto

Os scripts de ingestão precisam rodar de forma agendada em produção (BCB PIX é mensal; IBGE e Olist são cargas únicas). A solução precisa:
- Ser serverless (custo zero quando não executa)
- Ser containerizada para garantir reprodutibilidade entre local e produção
- Caber no free tier do GCP para um projeto de portfólio

## Justificativa

- Serverless — Cloud Run Jobs cobra apenas pelo tempo de execução; custo próximo de zero para jobs curtos e pouco frequentes
- Containerizado — o mesmo `Dockerfile` roda localmente e em produção; elimina "funciona na minha máquina"
- Cloud Scheduler gratuito até 3 jobs — cobre as 3 fontes com frequência diferente (Olist batch único, IBGE estável, BCB mensal)
- Sem infra permanente para gerenciar — sem VM, sem cluster, sem serviço sempre ligado

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| Cloud Composer (Airflow managed) | ~$300/mês de custo fixo — inviável para portfólio |
| Prefect Cloud | Fora do ecossistema GCP nativo; free tier limitado |
| Compute Engine (VM permanente) | Paga mesmo quando ocioso; requer gerenciamento de SO |
| Cloud Functions | Limite de 9 minutos por execução — insuficiente para coletas maiores; sem suporte a dependências complexas |

## Consequências

- Sem interface visual de DAGs em produção — monitoramento via Cloud Logging e alertas no GitHub Actions
- Deploy requer push de nova imagem Docker a cada mudança no script — `deploy.yml` no GitHub Actions automatiza isso
- Compatibilidade total com orquestração local via Makefile: mesmo script Python, orquestrador diferente

```
Local                   Produção
Makefile                Cloud Scheduler
    ↓                       ↓
python script.py        Cloud Run Job
    ↓                       ↓
         mesmo script Python
```
