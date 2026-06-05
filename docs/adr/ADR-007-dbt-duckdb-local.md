# ADR-007: dbt-duckdb como Adaptador Local na Fase 4a

**Status:** Aceito
**Data:** Junho/2026

---

## Decisão

Usar `dbt-duckdb` na fase Local A para rodar o dbt contra os Parquets locais sem dependência de cloud. Na fase Local B, migrar para `dbt-bigquery` com ajustes de dialeto SQL esperados e planejados.

## Contexto

O ciclo de desenvolvimento define três fases de produtização. A fase 4a precisa ser reproduzível sem credenciais de cloud — qualquer pessoa que clone o repositório deve conseguir rodar o pipeline de ponta a ponta localmente.

O DuckDB lê Parquet nativamente, elimina a necessidade de um warehouse para a fase local, e não requer instalação além do pacote Python.

## Riscos Conhecidos e Aceitos

O DuckDB e o BigQuery têm dialetos SQL distintos. Funções de data, janelas, tipos e comportamento de NULL podem divergir. Isso significa que modelos dbt validados na fase 4a podem precisar de ajustes na fase 4b — isso é **esperado e planejado**, não um defeito.

Mitigação: na fase 4b, testar cada modelo dbt contra BigQuery antes de avançar para a fase 4c.

## Consequências

- Fase 4a é completamente reproduzível sem conta GCP
- A migração de dialeto na fase 4b é explícita no roadmap e não deve ser tratada como retrabalho — é parte do ciclo
- O Streamlit local na fase 4a é protótipo contra DuckDB; o produto final aponta para BigQuery
