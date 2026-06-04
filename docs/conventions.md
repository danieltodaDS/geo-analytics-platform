# Convenções — Geo Analytics Platform

> Documento normativo. Toda contribuição ao projeto deve seguir estas convenções.
> Em caso de dúvida, consulte este documento antes de criar arquivos ou escrever código.

---

## Nomenclatura — Scripts de Ingestão

```
ingestion/src/{fonte}.py
```

| Script | Fonte |
|---|---|
| `olist.py` | Olist (Kaggle) |
| `ibge_localidades.py` | IBGE API Localidades |
| `ibge_censo.py` | IBGE SIDRA — Censo 2022 |
| `bcb_pix.py` | BCB PIX por Município |

Uma fonte = um script. Sem scripts genéricos que cobrem múltiplas fontes.

---

## Nomenclatura — Modelos dbt

### Staging

```
stg_{fonte}_{entidade}
```

| Modelo | Fonte | Entidade |
|---|---|---|
| `stg_olist_orders` | olist | pedidos |
| `stg_ibge_localidades` | ibge | municípios referencial |
| `stg_ibge_censo` | ibge | censo demográfico |
| `stg_bcb_pix` | bcb | transações PIX |

Regra: um modelo de staging por tabela raw. Sem joins no staging.

### Intermediate

```
int_{descricao_do_que_o_modelo_faz}
```

Exemplos:
- `int_olist_por_municipio` — Olist agregado por município/mês
- `int_municipios_enriquecidos` — join de covariáveis municipais
- `int_periodo_pre_pos` — definição de janelas do experimento

Regra: nome descreve a transformação ou o resultado, não a fonte de origem.

### Marts

```
mart_{entidade_de_negocio}
```

Exemplos:
- `mart_geo_lift` — dataset principal para o experimento causal
- `mart_municipios` — perfil completo por município

---

## Nomenclatura — BigQuery

### Datasets

```
{ambiente}_{dominio}
```

| Dataset | Ambiente | Domínio |
|---|---|---|
| `prod_raw` | prod | raw |
| `prod_staging` | prod | staging |
| `prod_intermediate` | prod | intermediate |
| `prod_marts` | prod | marts |
| `dev_raw` | dev | raw |
| `dev_staging` | dev | staging |

Ambientes: `prod`, `dev`. Nunca criar dataset sem prefixo de ambiente.

### Tabelas e colunas

- snake_case em tudo — sem camelCase, sem hífens
- Nomes descritivos — `id_municipio`, não `id` ou `mun_id`
- Chave primária sempre chamada `{entidade}_id` ou `id_{entidade}` — consistente dentro do modelo
- Datas: sufixo `_at` para timestamps (`criado_at`), sufixo `_data` para dates (`pedido_data`)

---

## Nomenclatura — Paths da Raw Layer

O padrão de path é o mesmo em todas as fases. O que muda é a raiz:

| Fase | Raiz |
|---|---|
| Local A (sem cloud) | `data/raw/` — filesystem local |
| Local B + Remoto | `gs://{GCS_BUCKET}/raw/` — Google Cloud Storage |

### Estrutura do path (igual em todas as fases)

```
{raiz}/{fonte}/year={YYYY}/month={MM}/day={DD}/data.parquet
```

| Fonte | Path relativo |
|---|---|
| IBGE Localidades | `ibge_localidades/year=X/month=X/day=X/data.parquet` |
| IBGE Censo 9606 | `ibge_censo_9606/year=X/month=X/day=X/data.parquet` |
| IBGE Censo 9605 | `ibge_censo_9605/year=X/month=X/day=X/data.parquet` |
| IBGE Censo 9514 | `ibge_censo_9514/year=X/month=X/day=X/data.parquet` |
| BCB PIX | `bcb_pix/year=X/month=X/day=X/data.parquet` |
| Olist | `olist/year=X/month=X/day=X/data.parquet` |

Regras:
- `month` e `day` sempre com dois dígitos zero-padded (`month=06`, não `month=6`)
- Data = data de execução do script (UTC), não data do dado
- Arquivo sempre chamado `data.parquet` — a partição está no path, não no nome
- O destino (local vs GCS) é controlado pela variável de ambiente `RAW_BASE_PATH`

---

## Nomenclatura — Python

### Arquivos e módulos

- snake_case: `ibge_localidades.py`, `bcb_pix.py`
- Testes espelham o módulo testado: `test_ibge_localidades.py`

### Classes Pydantic

- PascalCase com sufixo `Raw` para models de validação de ingestão: `MunicipioRaw`, `SidraRegistroRaw`, `PixTransacaoRaw`

### Funções

- snake_case: `coletar_localidades()`, `_parse_sidra()`
- Funções internas (não exportadas): prefixo `_`
- Funções de fetch HTTP: sempre decoradas com Tenacity

### Variáveis de ambiente

- UPPER_SNAKE_CASE: `GCS_BUCKET`, `KAGGLE_USERNAME`, `KAGGLE_KEY`
- Nunca hard-codar — sempre via `os.environ` ou `os.getenv`

---

## Commits Semânticos e Atômicos

### Tipos

| Prefixo | Uso |
|---|---|
| `feat:` | Nova funcionalidade de produção |
| `fix:` | Correção de bug |
| `refactor:` | Mudança de código sem alteração de comportamento |
| `test:` | Adição ou correção de testes |
| `docs:` | Documentação (ADR, spec, entendimento, README) |
| `chore:` | Manutenção (deps, config, CI) |

### Atomicidade

Um commit por unidade lógica de trabalho. Nunca agrupar etapas distintas do ciclo Explorar / Entender / Especificar / Produtizar em um único commit.

Exemplos corretos:
```
docs: entendimento da API IBGE Localidades
docs: spec de ingestão ibge_localidades.py
feat: implementa ibge_localidades.py com Pydantic e Tenacity
test: testes unitários de ibge_localidades.py
```

Exemplos incorretos:
```
feat: exploração + spec + implementação IBGE   ← agrupa etapas distintas
feat: tudo do IBGE                             ← vago e agrupado
```

---

*Atualizado: Junho/2026*
