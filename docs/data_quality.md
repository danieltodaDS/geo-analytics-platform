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
| Staging → Intermediate | Testes de PK passando (`not_null` + `unique`) |
| Intermediate → Marts | Testes de relacionamento e negócio passando |
| Marts → Consumo | Suite completa + documentação de catálogo presente |

---

## Testes Obrigatórios por Camada

### Staging

| Contexto | Teste dbt | Obrigatório |
|---|---|---|
| Toda coluna PK | `not_null` | ✅ |
| Toda coluna PK | `unique` | ✅ |

Staging não tem regras de negócio — os únicos testes são de integridade estrutural da chave.

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
