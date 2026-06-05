# Spec — Ingestão Olist (Feature 1)

> Pré-requisito: `docs/understanding/olist.md` revisado e fechado.
> Esta spec é o contrato entre exploração e produtização.
> Antes de gerar código, leia esta spec na íntegra.

---

## Escopo

Um script que lê as 8 tabelas Olist de CSVs locais, valida via Pydantic e grava um Parquet por tabela.

| Script | Fonte | Output raw |
|---|---|---|
| `ingestion/src/olist.py` | CSVs em `data/olist/` | 1 Parquet por tabela por execução |

**Sem API, sem retry, sem paginação** — carga batch de arquivos locais estáticos.

---

## Fases de Produtização

| Fase | O que muda | `RAW_BASE_PATH` |
|---|---|---|
| **4a — Local A** | Script grava Parquet em `data/raw/` local. | `data/raw` |
| **4b — Local B** | Parquet carregado no BigQuery via `bq load`. | `data/raw` |
| **4c — Remoto** | **Não se aplica.** | — |

O Olist é um dump histórico estático do Kaggle (2016–2018) — sem API, sem atualização, sem novos dados. Rodar o script uma segunda vez produz exatamente o mesmo Parquet. Na fase 4c, quando o restante do pipeline migra para Cloud Run, o Olist já está no BigQuery. Não há fase remota para esta fonte.

---

## Variáveis de ambiente

| Variável | Fases | Uso |
|---|---|---|
| `OLIST_BASE_PATH` | todas | Diretório dos CSVs de origem. Default: `data/olist` |
| `RAW_BASE_PATH` | todas | Raiz do path de saída dos Parquets |

---

## Paths de saída

```
{RAW_BASE_PATH}/olist_customers/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_orders/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_order_items/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_order_payments/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_order_reviews/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_geolocation/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_products/year={YYYY}/month={MM}/day={DD}/data.parquet
{RAW_BASE_PATH}/olist_sellers/year={YYYY}/month={MM}/day={DD}/data.parquet
```

- `YYYY/MM/DD` = data de execução (UTC)
- Se o path já existir, sobrescreve
- Formato: Parquet com compressão snappy

---

## Parse

```
CSV → pd.read_csv → validação Pydantic linha a linha → DataFrame → Parquet
```

Transformações permitidas: apenas as necessárias para salvar em Parquet (inferência de tipos do pandas). Sem casts explícitos, sem filtragens, sem renomeações — essas são responsabilidades do staging dbt.

Falha em qualquer tabela aborta o run inteiro — write parcial é pior que sem write.

**Performance:** a geolocation tem 1.000.163 linhas. A validação Pydantic linha a linha pode ser lenta — validar apenas uma amostra das primeiras 1.000 linhas é suficiente para garantir o schema. O restante é gravado diretamente do DataFrame sem validação individual.

---

## Modelos Pydantic

### `OlistCustomerRaw`

```python
class OlistCustomerRaw(BaseModel):
    customer_id: str
    customer_unique_id: str
    customer_zip_code_prefix: int
    customer_city: str
    customer_state: str
```

### `OlistOrderRaw`

```python
class OlistOrderRaw(BaseModel):
    order_id: str
    customer_id: str
    order_status: str
    order_purchase_timestamp: str
    order_approved_at: Optional[str] = None          # 160 nulos
    order_delivered_carrier_date: Optional[str] = None   # 1.783 nulos
    order_delivered_customer_date: Optional[str] = None  # 2.965 nulos
    order_estimated_delivery_date: str
```

Datas mantidas como string — cast para datetime é responsabilidade do staging dbt.

### `OlistOrderItemRaw`

```python
class OlistOrderItemRaw(BaseModel):
    order_id: str
    order_item_id: int
    product_id: str
    seller_id: str
    shipping_limit_date: str
    price: float
    freight_value: float
```

### `OlistOrderPaymentRaw`

```python
class OlistOrderPaymentRaw(BaseModel):
    order_id: str
    payment_sequential: int
    payment_type: str
    payment_installments: int
    payment_value: float
```

### `OlistOrderReviewRaw`

```python
class OlistOrderReviewRaw(BaseModel):
    review_id: str
    order_id: str
    review_score: int
    review_comment_title: Optional[str] = None    # 87.656 nulos
    review_comment_message: Optional[str] = None  # 58.247 nulos
    review_creation_date: str
    review_answer_timestamp: str
```

### `OlistGeolocationRaw`

```python
class OlistGeolocationRaw(BaseModel):
    geolocation_zip_code_prefix: int
    geolocation_lat: float
    geolocation_lng: float
    geolocation_city: str
    geolocation_state: str
```

Duplicatas por zip prefix mantidas no raw — deduplicação é responsabilidade do staging.

### `OlistProductRaw`

```python
class OlistProductRaw(BaseModel):
    product_id: str
    product_category_name: Optional[str] = None        # 610 nulos
    product_name_lenght: Optional[float] = None        # 610 nulos
    product_description_lenght: Optional[float] = None # 610 nulos
    product_photos_qty: Optional[float] = None         # 610 nulos
    product_weight_g: Optional[float] = None           # 2 nulos
    product_length_cm: Optional[float] = None          # 2 nulos
    product_height_cm: Optional[float] = None          # 2 nulos
    product_width_cm: Optional[float] = None           # 2 nulos
```

### `OlistSellerRaw`

```python
class OlistSellerRaw(BaseModel):
    seller_id: str
    seller_zip_code_prefix: int
    seller_city: str
    seller_state: str
```

---

## Logging — structlog

| Evento | Nível | Campos extras |
|---|---|---|
| Início do script | `info` | — |
| Início de cada tabela | `info` | `tabela` |
| Volume abaixo do esperado | `warning` | `tabela`, `total`, `minimo_esperado` |
| Parquet gravado | `info` | `tabela`, `destino_path` |
| Erro fatal em tabela | `error` | `tabela`, `exc_info=True` |

---

## Guardas de volume

| Tabela | Mínimo esperado |
|---|---|
| customers | 99.000 |
| orders | 99.000 |
| order_items | 112.000 |
| order_payments | 103.000 |
| order_reviews | 99.000 |
| geolocation | 1.000.000 |
| products | 32.000 |
| sellers | 3.000 |

---

## Testes obrigatórios

Arquivo: `ingestion/tests/test_olist.py`

| Teste | Descrição |
|---|---|
| `test_parse_customer_completo` | Record válido → `OlistCustomerRaw` correto |
| `test_parse_order_campos_opcionais` | Datas nulas → campos `Optional` aceitos sem erro |
| `test_parse_order_campo_obrigatorio_ausente` | `order_id` ausente → `ValidationError` |
| `test_parse_order_item_completo` | Record válido → `OlistOrderItemRaw` correto |
| `test_parse_payment_completo` | Record válido → `OlistOrderPaymentRaw` correto |
| `test_parse_review_campos_opcionais` | Comentários nulos → aceitos sem erro |
| `test_parse_geolocation_completo` | Record válido → `OlistGeolocationRaw` correto |
| `test_parse_product_campos_opcionais` | Atributos físicos nulos → aceitos sem erro |
| `test_parse_seller_completo` | Record válido → `OlistSellerRaw` correto |
| `test_volume_guard_warning` | Tabela `orders` com volume abaixo do mínimo → `log.warning` chamado |
| `test_volume_guard_ok` | Tabela `orders` com volume acima do mínimo → sem warning |

---

## Edge cases e tratamentos

| Situação | Tratamento |
|---|---|
| Datas em `orders` com nulo | `Optional[str]` — passar para downstream |
| Duplicatas em `geolocation` | Mantidas no raw — deduplicação no staging |
| `product_category_name` nulo | `Optional[str]` — passar para downstream |
| Atributos físicos de produto nulos | `Optional[float]` — 2 produtos sem peso/dimensões |
| Falha em qualquer tabela | Abortar run inteiro — não gravar parcial |

---

## O que esta spec não cobre

- Geocodificação zip prefix → IBGE → responsabilidade do `stg_olist_orders.sql`
- Filtragem por `order_status = 'delivered'` → responsabilidade do staging
- Corte temporal 2017–2018 → responsabilidade do staging
- Deduplicação de `geolocation` por zip prefix → responsabilidade do staging
- Cast de campos de data de string para datetime → responsabilidade do staging

---

*Spec fechada em: Junho/2026*
