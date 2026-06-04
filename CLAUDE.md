## Sobre o projeto
Pipeline de Analytics Engineering para Geo Lift
usando dados públicos brasileiros no GCP.

## Ciclo de desenvolvimento
Toda feature de produção segue: Explorar → Entender → Especificar → Produtizar.
A produtização segue três fases progressivas — nunca pule etapas:
  4a. Local A — script salva Parquet em data/raw/ local, dbt roda contra arquivos locais (sem cloud)
  4b. Local B — script salva Parquet local, dbt roda contra BigQuery
  4c. Remoto  — Cloud Run + GCS + BigQuery em produção
Antes de gerar código de produção, leia a spec correspondente em /specs.

## Stack
Python 3.11, dbt Core, BigQuery, GCS, Streamlit, Terraform

## Convenções obrigatórias
- Pydantic para validação de schema em toda ingestão
- Tenacity para retry em toda chamada de API
- Logging estruturado com structlog
- Nunca hardcodar credenciais — usar variáveis de ambiente
- Commits semânticos e atômicos — um commit por unidade lógica de trabalho (ex: um arquivo, uma decisão, uma etapa do ciclo). Nunca agrupar etapas distintas do ciclo Explorar/Entender/Especificar/Produtizar em um único commit.

## Testes obrigatórios
- not_null + unique em toda PK
- Teste unitário cobrindo edge cases da spec