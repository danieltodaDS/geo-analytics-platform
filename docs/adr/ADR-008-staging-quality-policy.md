# ADR-008 — Política de Qualidade na Camada Staging

**Status:** Aceito
**Data:** Junho/2026

## Contexto

A camada staging tem como contrato ser uma réplica fiel da fonte com transformações técnicas mínimas (cast, rename, remoção de colunas de partição). A questão é: quais garantias de qualidade devem ser impostas nessa camada?

A abordagem anterior exigia `not_null + unique` em toda PK de staging, herdando o padrão do dbt style guide. Isso cria dois problemas:

1. `unique` impõe uma garantia que depende do comportamento da fonte — fora do controle do pipeline
2. Confunde responsabilidades: decidir qual versão de um registro vence é lógica de negócio e pertence ao intermediate

## Decisão

Staging aplica apenas `not_null` nos identificadores mínimos que confirmam que o dado chegou e é identificável.

`unique` não é testado em staging.

A responsabilidade de deduplicação é dividida em dois níveis:

**Duplicata técnica** (linha byte-a-byte idêntica, causada por retry ou reprocessamento de pipeline): removida em staging via `QUALIFY ROW_NUMBER() OVER (PARTITION BY <todas as colunas não-técnicas>) = 1`. É ruído de infraestrutura, não decisão de negócio.

**Duplicata semântica** (mesma entidade, versões diferentes do registro): removida exclusivamente no intermediate, onde há contexto de negócio para decidir qual versão vence.

## Consequências

- Staging nunca bloqueia o pipeline por falha de unicidade na fonte
- A garantia de unicidade é fornecida pelo intermediate, que testa `not_null + unique` na PK com severidade `error`
- O critério de promoção Staging → Intermediate é: `not_null` nos identificadores-chave passando

## Alternativas consideradas

**Manter `not_null + unique` em staging:** rejeitado — impõe garantias que dependem do comportamento da fonte e mistura responsabilidades de infraestrutura com lógica de negócio.

**Não testar nada em staging:** rejeitado — `not_null` nos identificadores mínimos é necessário para confirmar que o dado chegou identificável e que a ingestão não produziu registros fantasma.
