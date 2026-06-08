# ADR-008 — Política de Qualidade na Camada Staging

**Status:** Aceito
**Data:** Junho/2026

## Contexto

A camada staging tem como contrato ser uma réplica fiel da fonte com transformações técnicas mínimas (cast, rename, remoção de colunas de partição). A questão é: quais garantias de qualidade devem ser impostas nessa camada?

A abordagem anterior exigia `not_null + unique` em toda PK de staging, herdando o padrão do dbt style guide. Isso cria dois problemas:

1. `unique` impõe uma garantia que depende do comportamento da fonte — fora do controle do pipeline
2. Confunde responsabilidades: decidir qual versão de um registro vence é lógica de negócio e pertence ao intermediate

## Decisão

Todo modelo de staging recebe uma coluna `row_hash`: `md5` de todas as colunas de negócio (excluindo colunas de partição `year/month/day`), com `coalesce(..., '')` para NULLs.

O `row_hash` serve dois propósitos com uma única coluna:

**Dedup técnica:** `QUALIFY ROW_NUMBER() OVER (PARTITION BY row_hash) = 1` remove linhas byte-a-byte idênticas antes de qualquer transformação. Obrigatório em todos os modelos de staging.

**Idempotência em cargas incrementais:** em produção (BigQuery + carga incremental), o `row_hash` é o mecanismo de controle — nova partição é inserida somente se `row_hash` ainda não existe na tabela. Sem ele, reprocessamentos gerariam duplicatas que cruzariam para intermediate.

O `row_hash` é testado com `not_null + unique` em todos os modelos de staging.

PKs naturais da fonte (ex: `customer_id`, `order_id`) recebem apenas `not_null` em staging — `unique` é garantido no intermediate após dedup semântica. A responsabilidade de unicidade de negócio pertence ao intermediate, não ao staging.

A responsabilidade de deduplicação é dividida em dois níveis:

**Duplicata técnica** (linha byte-a-byte idêntica): removida em staging via `row_hash` + `QUALIFY`. É ruído de infraestrutura, não decisão de negócio.

**Duplicata semântica** (mesma entidade, versões diferentes do registro): removida exclusivamente no intermediate, onde há contexto de negócio para decidir qual versão vence.

## Consequências

- Staging nunca bloqueia o pipeline por falha de unicidade na PK natural da fonte
- `row_hash` único em staging garante que intermediate recebe dado limpo de duplicatas técnicas
- PKs naturais têm `not_null + unique` testados no intermediate — onde a garantia é significativa
- O critério de promoção Staging → Intermediate é: `not_null` e `unique` em `row_hash` passando

## Alternativas consideradas

**`not_null + unique` na PK natural em staging:** rejeitado — impõe garantia que depende do comportamento da fonte; mistura responsabilidade de infraestrutura com lógica de negócio.

**Não testar nada em staging:** rejeitado — `row_hash` com `not_null + unique` é necessário para confirmar idempotência e ausência de duplicatas técnicas antes de promover para intermediate.

**QUALIFY PARTITION BY todas as colunas (sem row_hash):** rejeitado — funciona para dedup técnica local, mas não serve como mecanismo de idempotência em modelos incrementais no BigQuery.
