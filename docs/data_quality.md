# Política de Qualidade de Dados

> Define os testes obrigatórios, critérios de freshness, política de catálogo e integração de alertas para o projeto.
> Todo modelo dbt deve satisfazer os requisitos da sua camada antes de ser promovido.

---

## Princípio Central

> Dado com problema para no estágio onde o problema foi detectado.
> Nunca promove dado inválido para a camada seguinte.

---

## Critérios de Promoção entre Camadas

| Transição | Critério |
|---|---|
| Fonte → Raw | Schema válido (Pydantic) |
| Raw → Staging | Carga bem-sucedida no GCS e no BigQuery |
| Staging → Intermediate | `not_null` nos identificadores-chave passando; dado chegou íntegro |
| Intermediate → Marts | Testes de relacionamento e negócio passando |
| Marts → Consumo | Suite completa + documentação de catálogo presente |

---

## Testes Obrigatórios por Camada

### Staging

Staging espelha a fonte com dedup técnica e mecanismo de idempotência para cargas incrementais.

| Contexto | Teste dbt | Obrigatório |
|---|---|---|
| `row_hash` (md5 all cols) | `not_null` + `unique` | ✅ |
| PK natural da fonte | `not_null` | ✅ |
| Unicidade da PK natural | não testada em staging | ❌ |

`row_hash` é adicionado a todos os modelos de staging. Serve como fingerprint da linha (dedup técnica via `QUALIFY`) e como mecanismo de idempotência em cargas incrementais — nova partição é inserida somente se `row_hash` ainda não existe. Unicidade da PK natural é garantida no intermediate, após dedup semântica. Ver ADR-008.

### Intermediate

| Contexto | Teste dbt | Obrigatório |
|---|---|---|
| Toda PK | `not_null` + `unique` | ✅ |
| Toda FK | `relationships` | ✅ |
| Campos booleanos / status | `accepted_values` | ✅ |
| Métricas numéricas de negócio | `expression_is_true (valor > 0)` | ✅ |

### Marts

| Contexto | Teste dbt | Obrigatório |
|---|---|---|
| Toda PK | `not_null` + `unique` | ✅ |
| Toda FK | `relationships` | ✅ |
| Campos de status / categoria | `accepted_values` | ✅ |
| Métricas numéricas | `expression_is_true (valor > 0)` | ✅ |
| Volume mínimo | `dbt_utils.expression_is_true` ou Elementary | ✅ |

---

## Política de Deduplicação

### Duplicata técnica
Definição: linha byte-a-byte idêntica, originada por retry ou reprocessamento de pipeline — não representa uma entidade diferente.
Onde remover: **staging** — obrigatório. É ruído de infraestrutura, não lógica de negócio.
Como implementar:
```sql
QUALIFY ROW_NUMBER() OVER (PARTITION BY <todas as colunas não-técnicas>) = 1
```

### Duplicata semântica
Definição: mesma entidade de negócio com versões diferentes do registro (ex: mesmo cliente com endereço atualizado, mesmo pedido com status diferente).
Onde remover: **intermediate** — e somente intermediate.
Como implementar:
```sql
QUALIFY ROW_NUMBER() OVER (PARTITION BY <chave de negócio> ORDER BY <updated_at> DESC) = 1
```

Regra: staging nunca remove duplicata semântica. A decisão de qual versão vence é uma regra de negócio e pertence ao intermediate.

---

## Freshness por Source

Configurado em `sources.yml`. Valores por fonte:

| Source | warn_after | error_after |
|---|---|---|
| `olist` | — (batch única, sem freshness) | — |
| `ibge_localidades` | 90 dias | 180 dias |
| `ibge_censo_*` | 90 dias | 180 dias |
| `bcb_pix` | 1 dia | 3 dias |

`loaded_at_field` deve apontar para a coluna de partição de data de ingestão em cada tabela raw.

---

## Política de Catálogo

Obrigatório em **staging** e **marts**. Opcional em intermediate.

### Por modelo

```yaml
models:
  - name: mart_geo_lift
    description: "Dataset principal para o experimento causal de Geo Lift."
    meta:
      owner: daniel
    tags: [marts, geo_lift]
```

### Por coluna

Exemplo de mart (onde `unique` é obrigatório):
```yaml
columns:
  - name: id_municipio
    description: "Código IBGE do município (7 dígitos). Chave primária."
    tests:
      - not_null
      - unique
```

Regra: `description` obrigatório em toda coluna exposta no mart. Coluna sem descrição = modelo incompleto = não promovido.

---

## Elementary — Monitoramento Automático

Elementary detecta automaticamente anomalias não cobertas por testes estáticos.

### Monitores a ativar

| Monitor | Modelos | Threshold |
|---|---|---|
| Anomalia de volume | Todos os marts | ±30% da média histórica |
| Schema change | Todos os marts | Qualquer remoção de coluna |
| Freshness | Sources com SLA definido | Conforme tabela acima |

### Configuração no dbt

```yaml
# packages.yml
packages:
  - package: elementary-data/elementary
    version: [">=0.10.0", "<0.11.0"]
```

```yaml
# dbt_project.yml
models:
  +meta:
    elementary:
      timestamp_column: "data_ingestao"
```

---

## Testes Unitários — Ingestão Python

Arquivo: `ingestion/tests/test_{fonte}.py`

Obrigatório por script de ingestão:

| Categoria | O que testar |
|---|---|
| Parse / validação Pydantic | Record válido → model correto |
| Parse / validação Pydantic | Record inválido → `ValidationError` |
| Edge cases documentados na spec | Um teste por edge case listado |
| Retry | Tenacity retenta em 5xx, não retenta em 4xx |
| Guard de volume | Warning logado quando `len < threshold` |

---

## Integração com CI — GitHub Actions

### `ci.yml` — todo Pull Request

```
pytest ingestion/tests/
dbt compile
dbt test
terraform plan
```

Falha em qualquer step bloqueia o merge.

### Alerta de freshness

Elementary gera relatório de qualidade via `edr send-report`. Integrar com notificação no `ci.yml` após merge na `main`.

---

*Atualizado: Junho/2026*
