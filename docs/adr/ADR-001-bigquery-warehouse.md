# ADR-001: BigQuery como Warehouse

**Status:** Aceito
**Data:** Junho/2026

---

## Decisão

Usar BigQuery como warehouse principal do projeto.

## Contexto

O projeto precisa de um warehouse que suporte:
- Carga direta de arquivos Parquet do GCS sem ETL intermediário
- Queries analíticas sobre dados municipais (~5.570 municípios × múltiplas covariáveis)
- Integração com dbt Core para transformações
- Custo compatível com portfólio (sem cluster permanente)

## Justificativa

- Integração nativa com GCS — `bq load` carrega Parquet diretamente, sem pipeline de ETL adicional
- Serverless — sem cluster para provisionar ou gerenciar; cobra por query executada
- Free tier de 1TB/mês de queries cobre com folga o volume do projeto
- Integração nativa com Streamlit via `google-cloud-bigquery` e `db-dtypes`
- Padrão do mercado brasileiro em empresas de produto digital — relevante para portfólio

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| Snowflake | Multi-cloud irrelevante para stack 100% GCP; custo maior no free tier |
| Cloud Spanner | OLTP, não OLAP — projetado para transações, não queries analíticas |
| Redshift | Fora do ecossistema GCP; sem vantagem para este contexto |
| DuckDB local | Não resolve o ambiente remoto (Cloud Run); sem free tier de armazenamento persistente |

## Consequências

- Stack inteira no ecossistema GCP — aceitável para projeto de portfólio focado em GCP
- Atenção a scan de colunas em tabelas grandes — usar `SELECT` explícito, nunca `SELECT *` em produção
- Particionamento por data de ingestão nas tabelas raw para controlar custo de queries históricas
