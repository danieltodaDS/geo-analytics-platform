# Spec — Ingestão IBGE (Feature 2)

> Pré-requisito: `docs/understanding/ibge.md` revisado e fechado.
> Esta spec é o contrato entre exploração e produtização.
> Antes de gerar código, leia esta spec na íntegra.

---

## Escopo

Dois scripts independentes:

| Script | Fonte | Output raw |
|---|---|---|
| `ingestion/src/ibge_localidades.py` | API Localidades | 1 Parquet por execução |
| `ingestion/src/ibge_censo.py` | SIDRA tabelas 9606, 9605, 9514 | 1 Parquet por tabela por execução |

---

## Fases de Produtização

Os scripts são implementados uma vez e executados nas três fases progressivas. O que muda entre fases é o destino do Parquet, não a lógica dos scripts.

| Fase | O que muda | `RAW_BASE_PATH` |
|---|---|---|
| **4a — Local A** | Scripts gravam Parquet em `data/raw/` local. dbt roda contra arquivos locais. Sem dependência de cloud. | `data/raw` |
| **4b — Local B** | Scripts gravam Parquet em `data/raw/` local (inalterado). Parquet é carregado no BigQuery via `bq load`. dbt roda contra BigQuery. | `data/raw` |
| **4c — Remoto** | Scripts rodam em Cloud Run. Parquet gravado diretamente no GCS. BigQuery carrega do GCS. dbt roda contra BigQuery. | `gs://{GCS_BUCKET}/raw` |

**Critério para avançar de fase:** cada fase só inicia após a anterior passar em todos os testes.

---

## Variáveis de ambiente

| Variável | Fases | Uso |
|---|---|---|
| `RAW_BASE_PATH` | 4a, 4b, 4c | Raiz do path de saída. `data/raw` (local) ou `gs://{GCS_BUCKET}/raw` (GCS) |
| `GCS_BUCKET` | 4c | Nome do bucket GCS (sem `gs://`) — usado para montar `RAW_BASE_PATH` em produção |
| `GOOGLE_APPLICATION_CREDENTIALS` | 4b, 4c | Resolvido automaticamente pelo SDK GCP — não injetar no código |

---

## Paths de saída

```
{RAW_BASE_PATH}/ibge_localidades/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/ibge_censo_9606/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/ibge_censo_9605/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/ibge_censo_9514/year={YYYY}/month={MM}/day={DD}/data.parquet
```

- `YYYY/MM/DD` = data de execução do script (UTC)
- Se o path já existir, sobrescreve — a data de execução é o controle de idempotência
- Formato: Parquet com compressão snappy

---

## Script 1 — `ibge_localidades.py`

### Responsabilidade

Coletar todos os municípios da API de Localidades, validar o schema via Pydantic e gravar em Parquet no destino definido por `RAW_BASE_PATH`.

### Endpoint

```
GET https://servicodados.ibge.gov.br/api/v1/localidades/municipios
Timeout: 30s
Auth: nenhuma
Paginação: nenhuma — retorna tudo em uma chamada
```

### Parse

O JSON retorna objetos aninhados com duas hierarquias geográficas paralelas. O parse faz o flatten para uma linha por município, capturando os campos de ambas as hierarquias:

```
JSON bruto → flatten → validação Pydantic → DataFrame → Parquet
```

### Pydantic model — `MunicipioRaw`

```python
from pydantic import BaseModel

class MunicipioRaw(BaseModel):
    id_municipio: int
    nome_municipio: str
    # Hierarquia nova — regiao-imediata (divisão IBGE desde 2017)
    regiao_imediata_id: int
    regiao_imediata_nome: str
    regiao_interm_id: int
    regiao_interm_nome: str
    uf_id: int
    uf_sigla: str
    uf_nome: str
    macroregiao_id: int
    macroregiao_sigla: str
    macroregiao_nome: str
    # Hierarquia antiga — microrregiao (divisão IBGE até 2017)
    microrregiao_id: int
    microrregiao_nome: str
    mesorregiao_id: int
    mesorregiao_nome: str
```

Mapeamento JSON → campos do model:

| Campo model | Caminho no JSON bruto |
|---|---|
| `id_municipio` | `m["id"]` |
| `nome_municipio` | `m["nome"]` |
| `regiao_imediata_id` | `m["regiao-imediata"]["id"]` |
| `regiao_imediata_nome` | `m["regiao-imediata"]["nome"]` |
| `regiao_interm_id` | `m["regiao-imediata"]["regiao-intermediaria"]["id"]` |
| `regiao_interm_nome` | `m["regiao-imediata"]["regiao-intermediaria"]["nome"]` |
| `uf_id` | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["id"]` |
| `uf_sigla` | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["sigla"]` |
| `uf_nome` | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["nome"]` |
| `macroregiao_id` | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["regiao"]["id"]` |
| `macroregiao_sigla` | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["regiao"]["sigla"]` |
| `macroregiao_nome` | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["regiao"]["nome"]` |
| `microrregiao_id` | `m["microrregiao"]["id"]` |
| `microrregiao_nome` | `m["microrregiao"]["nome"]` |
| `mesorregiao_id` | `m["microrregiao"]["mesorregiao"]["id"]` |
| `mesorregiao_nome` | `m["microrregiao"]["mesorregiao"]["nome"]` |

### Retry — Tenacity

```python
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception

def _retryable(exc: BaseException) -> bool:
    if isinstance(exc, requests.HTTPError):
        return exc.response.status_code >= 500
    return isinstance(exc, (requests.ConnectionError, requests.Timeout))

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception(_retryable),
    reraise=True,
)
```

- Retenta: `ConnectionError`, `Timeout`, `HTTPError` 5xx
- Não retenta: `HTTPError` 4xx — falha imediatamente
- Após esgotar tentativas: relança a exceção (`reraise=True`)

### Logging — structlog

| Evento | Nível | Campos extras |
|---|---|---|
| Início da coleta | `info` | — |
| Fetch concluído | `info` | `total_municipios` |
| Volume abaixo do esperado | `warning` | `total`, `minimo_esperado=5500` |
| Parquet gravado | `info` | `destino_path` |
| Erro fatal | `error` | `exc_info=True` |

### Guarda de volume

Se `len(records) < 5500`: logar `warning` e continuar — não abortar. O IBGE pode ter atualizado a base. O pipeline não deve falhar silenciosamente nem interromper por flutuação de volume.

---

## Script 2 — `ibge_censo.py`

### Responsabilidade

Coletar as três tabelas do Censo 2022 via SIDRA, validar via Pydantic e gravar um Parquet por tabela no destino definido por `RAW_BASE_PATH`.

### Endpoints

```
GET https://apisidra.ibge.gov.br/values/t/9606/n6/all/v/all/p/last
GET https://apisidra.ibge.gov.br/values/t/9605/n6/all/v/all/p/last
GET https://apisidra.ibge.gov.br/values/t/9514/n6/all/v/all/p/last

Timeout: 60s  (resposta maior que Localidades)
Auth: nenhuma
Paginação: nenhuma — retorna tudo em uma chamada
Sleep entre chamadas: 0.5s  (respeitar rate limit)
```

### Parse — `_parse_sidra`

A API SIDRA tem comportamento especial: `data[0]` é o mapa de cabeçalho (chave interna → nome legível), não um registro. `data[1:]` são os registros reais.

```
API response → strip data[0] → data[1:] com chaves internas → validação Pydantic → DataFrame → Parquet
```

**O raw layer armazena as chaves internas** (`NC`, `NN`, `V`, `D1C`, `D1N`, etc.) — não os nomes legíveis. A renomeação para nomes legíveis é responsabilidade do staging dbt.

O mapeamento completo de chaves internas → nomes legíveis por tabela está documentado em `docs/understanding/ibge.md`.

### Pydantic model — `SidraRegistroRaw`

Modelo único para as três tabelas. Campos `D5*` e `D6*` são opcionais pois a tabela 9605 tem apenas 4 dimensões.

```python
from typing import Optional
from pydantic import BaseModel

class SidraRegistroRaw(BaseModel):
    NC: str   # Nível Territorial (Código)
    NN: str   # Nível Territorial
    MC: str   # Unidade de Medida (Código)
    MN: str   # Unidade de Medida
    V: Optional[str]  # Valor — None se "-" ou "..."
    D1C: str  # Município (Código)
    D1N: str  # Município
    D2C: str  # Variável (Código)
    D2N: str  # Variável
    D3C: str  # Ano (Código)
    D3N: str  # Ano
    D4C: str  # Dimensão 4 (Código)
    D4N: str  # Dimensão 4
    D5C: Optional[str] = None  # Dimensão 5 — apenas 9606 e 9514
    D5N: Optional[str] = None
    D6C: Optional[str] = None  # Dimensão 6 — apenas 9606 e 9514
    D6N: Optional[str] = None
```

**Tratamento do campo `V` antes da validação Pydantic:**
- Se `V in ("-", "...")` → converter para `None`
- Caso contrário → manter a string como veio (o cast para numérico é responsabilidade do staging)

### Retry — Tenacity

Mesma configuração do `ibge_localidades.py`. Aplicar o decorator na função de fetch HTTP, não no loop de tabelas.

### Logging — structlog

| Evento | Nível | Campos extras |
|---|---|---|
| Início da coleta de uma tabela | `info` | `tabela` |
| Fetch concluído | `info` | `tabela`, `total_registros` |
| Volume abaixo do esperado | `warning` | `tabela`, `total`, `minimo_esperado=11000` |
| Parquet gravado | `info` | `tabela`, `destino_path` |
| Erro fatal em uma tabela | `error` | `tabela`, `exc_info=True` |

### Guarda de volume

Se `len(records) < 11000` para qualquer tabela: logar `warning` e continuar.

---

## Testes obrigatórios

Arquivo: `ingestion/tests/test_ibge.py`

### `ibge_localidades.py`

| Teste | Descrição |
|---|---|
| `test_parse_municipio_campos_obrigatorios` | Record completo → `MunicipioRaw` válido |
| `test_parse_municipio_sem_regiao_imediata` | Record sem `regiao-imediata` → `ValidationError` |
| `test_parse_municipio_id_tipo_correto` | `id_municipio` é `int`, não `str` |
| `test_volume_guard_warning` | `len < 5500` → `log.warning` chamado |
| `test_volume_guard_ok` | `len >= 5500` → sem warning |

### `ibge_censo.py`

| Teste | Descrição |
|---|---|
| `test_parse_sidra_strip_header` | `data[0]` não vira registro — total de registros = `len(data) - 1` |
| `test_parse_sidra_valor_suprimido_traco` | `V = "-"` → `None` no model |
| `test_parse_sidra_valor_suprimido_reticencias` | `V = "..."` → `None` no model |
| `test_parse_sidra_valor_numerico` | `V = "21494"` → string `"21494"` preservada (cast é do staging) |
| `test_parse_sidra_tabela_9605_sem_d5_d6` | Registros sem `D5C/D6C` → campos `None` sem erro |
| `test_parse_sidra_tabela_9606_com_d5_d6` | Registros com `D5C/D6C` → campos preenchidos |
| `test_volume_guard_warning` | `len < 11000` → `log.warning` chamado |
| `test_retry_5xx` | Tenacity retenta em HTTPError 500 |
| `test_sem_retry_4xx` | Tenacity não retenta em HTTPError 404 |

---

## Edge cases e tratamentos definidos

| Situação | Tratamento |
|---|---|
| `V = "-"` ou `V = "..."` no SIDRA | Converter para `None` antes do Pydantic |
| `data[0]` incluído no DataFrame | Proibido — `_parse_sidra` deve sempre operar sobre `data[1:]` |
| `len(municípios) < 5500` | `log.warning` — não abortar |
| `len(registros_sidra) < 11000` por tabela | `log.warning` — não abortar |
| `HTTPError` 4xx (endpoint errado, tabela inexistente) | Falha imediata sem retry — logar `error` |
| `HTTPError` 5xx ou timeout | Retry com backoff (até 3 tentativas) |
| Chave JSON com hífen (`regiao-imediata`) | Acessar via `m["regiao-imediata"]` — nunca via atributo |

---

## O que esta spec não cobre

- Renomeação de colunas do SIDRA para nomes legíveis → responsabilidade do `stg_ibge_censo.sql`
- Cast de tipos (`D1C` → `INT64`, `V` → `FLOAT64`, `D3C` → `INT64`) → responsabilidade do staging dbt
- `NULLIF` para suprimir valores `"-"` e `"..."` no warehouse → responsabilidade do staging dbt

---

*Spec fechada em: Junho/2026*
