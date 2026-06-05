# Spec — Ingestão BCB PIX (Feature 3)

> Pré-requisito: `docs/understanding/bcb_pix.md` revisado e fechado.
> Esta spec é o contrato entre exploração e produtização.
> Antes de gerar código, leia esta spec na íntegra.

---

## Escopo

Um script que coleta a série completa de transações PIX por município, valida via Pydantic e grava em Parquet no destino definido por `RAW_BASE_PATH`.

| Script | Fonte | Output raw |
|---|---|---|
| `ingestion/src/bcb_pix.py` | BCB OData — TransacoesPixPorMunicipio | 1 Parquet por execução |

---

## Fases de Produtização

| Fase | O que muda | `RAW_BASE_PATH` |
|---|---|---|
| **4a — Local A** | Script grava Parquet em `data/raw/` local. dbt roda contra arquivos locais. | `data/raw` |
| **4b — Local B** | Script grava Parquet local (inalterado). Parquet carregado no BigQuery via `bq load`. dbt roda contra BigQuery. | `data/raw` |
| **4c — Remoto** | Script roda em Cloud Run. Parquet gravado no GCS. BigQuery carrega do GCS. | `gs://{GCS_BUCKET}/raw` |

---

## Variáveis de ambiente

| Variável | Fases | Uso |
|---|---|---|
| `RAW_BASE_PATH` | 4a, 4b, 4c | Raiz do path de saída |
| `GCS_BUCKET` | 4c | Nome do bucket GCS (sem `gs://`) |
| `GOOGLE_APPLICATION_CREDENTIALS` | 4b, 4c | Resolvido automaticamente pelo SDK GCP — não injetar no código |

---

## Path de saída

```
{RAW_BASE_PATH}/bcb_pix/year={YYYY}/month={MM}/day={DD}/data.parquet
```

- `YYYY/MM/DD` = data de execução do script (UTC)
- Se o path já existir, sobrescreve — a data de execução é o controle de idempotência
- Formato: Parquet com compressão snappy

---

## Endpoint

```
GET https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata
    /TransacoesPixPorMunicipio(DataBase='202011')
    ?$format=json

Timeout: 120s  (resposta de ~25 MB)
Auth: nenhuma
Paginação: nenhuma — retorna tudo em uma chamada
DataBase: fixo em '202011' (lançamento do PIX) — captura a série completa
```

---

## Parse

```
API response → data["value"] → filtrar nulos → validação Pydantic → DataFrame → Parquet
```

Registros com `Municipio_Ibge` nulo (1 por mês, provável agregado do BCB) são descartados antes da validação Pydantic. O total descartado deve ser logado.

---

## Pydantic model — `PixMunicipioRaw`

Os campos preservam o `PascalCase` original da API — mesma convenção adotada no SIDRA (`NC`, `D1C`, `V`): o raw layer armazena as chaves como vieram da fonte; renomeação para `snake_case` é responsabilidade do staging dbt.

```python
from pydantic import BaseModel, field_validator

class PixMunicipioRaw(BaseModel):
    AnoMes: int
    Municipio_Ibge: int       # chega como float na API — cast via validator
    Municipio: str
    Estado_Ibge: int          # chega como float na API — cast via validator
    Estado: str
    Sigla_Regiao: str
    Regiao: str
    VL_PagadorPF: float
    QT_PagadorPF: int
    VL_PagadorPJ: float
    QT_PagadorPJ: int
    VL_RecebedorPF: float
    QT_RecebedorPF: int
    VL_RecebedorPJ: float
    QT_RecebedorPJ: int
    QT_PES_PagadorPF: int
    QT_PES_PagadorPJ: int
    QT_PES_RecebedorPF: int
    QT_PES_RecebedorPJ: int

    @field_validator("Municipio_Ibge", "Estado_Ibge", mode="before")
    @classmethod
    def cast_float_to_int(cls, v):
        # Pré-condição: v não é None — registros nulos são filtrados antes de chegar aqui
        return int(v)
```

`Municipio_Ibge` e `Estado_Ibge` chegam como `float` porque o pandas infere o tipo quando há nulos na coluna. O validator faz o cast antes da validação do tipo. **O filtro de nulos no parse é o guardião dessa pré-condição** — se `None` chegar aqui, `int(None)` vai lançar `TypeError`.

---

## Retry — Tenacity

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
- Não retenta: `HTTPError` 4xx
- Após esgotar tentativas: relança a exceção (`reraise=True`)

---

## Logging — structlog

| Evento | Nível | Campos extras |
|---|---|---|
| Início da coleta | `info` | — |
| Fetch concluído | `info` | `total_registros` |
| Registros nulos descartados | `info` | `total_descartados` |
| Volume abaixo do esperado | `warning` | `total`, `minimo_esperado=378000` |
| Parquet gravado | `info` | `destino_path` |
| Erro fatal | `error` | `exc_info=True` |

---

## Guarda de volume

Se `len(records) < 378000`: logar `warning` e continuar. A série cresce mensalmente — o threshold deve ser revisado a cada trimestre ou sempre que a série ultrapassar 400.000 registros.

---

## Testes obrigatórios

Arquivo: `ingestion/tests/test_bcb_pix.py`

| Teste | Descrição |
|---|---|
| `test_parse_registro_completo` | Registro válido → `PixMunicipioRaw` correto |
| `test_parse_municipio_ibge_tipo_correto` | `Municipio_Ibge` é `int`, não `float` |
| `test_parse_descarta_registro_nulo` | Lista com 1 registro nulo e 1 válido → resultado contém apenas o válido (nulo não aparece no output) |
| `test_volume_guard_warning` | `len < 378000` → `log.warning` chamado |
| `test_volume_guard_ok` | `len >= 378000` → sem warning |
| `test_retry_5xx` | Tenacity retenta em HTTPError 500 |
| `test_sem_retry_4xx` | Tenacity não retenta em HTTPError 404 |

---

## Edge cases e tratamentos

| Situação | Tratamento |
|---|---|
| `Municipio_Ibge` nulo (1 por mês) | Descartar antes do Pydantic — não é registro municipal |
| `Municipio_Ibge` e `Estado_Ibge` chegam como `float` | Cast para `int` via `field_validator` no Pydantic |
| Município sem registro em algum mês | Dado ausente = sem atividade naquele mês — não é erro |
| `HTTPError` 4xx | Falha imediata sem retry |
| `HTTPError` 5xx ou timeout | Retry com backoff (até 3 tentativas) |

---

## O que esta spec não cobre

- Agregação de PIX como covariável (média mensal por município) → responsabilidade do `stg_bcb_pix.sql`
- Cast de `AnoMes` para tipo data → responsabilidade do staging dbt
- Alinhamento temporal com Olist: PIX (2020+) não se sobrepõe a Olist (2015–2018) — PIX é covariável de perfil, não série temporal alinhada

---

*Spec fechada em: Junho/2026*
