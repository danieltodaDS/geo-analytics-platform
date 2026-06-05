# Understanding — BCB PIX

> Resultado da exploração em `exploration/bcb_exploration.ipynb`.
> Base para a spec em `specs/ingestion/bcb_pix.md`.

---

## Endpoint

```
GET https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata
    /TransacoesPixPorMunicipio(DataBase='{YYYYMM}')
    ?$format=json
```

O parâmetro `DataBase` define o mês inicial da série. Usar `'202011'` para capturar desde o lançamento do PIX (novembro/2020).

**Paginação:** nenhuma. A API retorna todos os registros em uma única resposta. `@odata.nextLink` não está presente. Com `DataBase='202011'`, a resposta tem 378.731 registros (~25 MB).

**Auth:** nenhuma.

**Timeout recomendado:** 120s — resposta grande.

---

## Schema real

| Campo | Tipo na API | Observação |
|---|---|---|
| `AnoMes` | `int64` | formato YYYYMM |
| `Municipio_Ibge` | `float64` | chega como float por causa de nulos — cast para int no Pydantic |
| `Municipio` | `str` | nome em caixa alta |
| `Estado_Ibge` | `float64` | chega como float por causa de nulos — cast para int no Pydantic |
| `Estado` | `str` | nome por extenso em caixa alta |
| `Sigla_Regiao` | `str` | nulo nos mesmos registros de `Municipio_Ibge` nulo |
| `Regiao` | `str` | |
| `VL_PagadorPF` | `float64` | valor total pago por pessoas físicas |
| `QT_PagadorPF` | `int64` | quantidade de transações pagas por PF |
| `VL_PagadorPJ` | `float64` | valor total pago por pessoas jurídicas |
| `QT_PagadorPJ` | `int64` | quantidade de transações pagas por PJ |
| `VL_RecebedorPF` | `float64` | valor total recebido por PF |
| `QT_RecebedorPF` | `int64` | quantidade de transações recebidas por PF |
| `VL_RecebedorPJ` | `float64` | valor total recebido por PJ |
| `QT_RecebedorPJ` | `int64` | quantidade de transações recebidas por PJ |
| `QT_PES_PagadorPF` | `int64` | pessoas físicas únicas pagadoras |
| `QT_PES_PagadorPJ` | `int64` | pessoas jurídicas únicas pagadoras |
| `QT_PES_RecebedorPF` | `int64` | pessoas físicas únicas recebedoras |
| `QT_PES_RecebedorPJ` | `int64` | pessoas jurídicas únicas recebedoras |

---

## Cobertura e período

- **Municípios:** 5.571 distintos — cobertura completa de todos os municípios brasileiros
- **Período:** novembro/2020 (lançamento do PIX) até mês corrente
- **Lag de publicação:** mínimo — dado do mês corrente já disponível na API
- **Meses distintos:** 68 (202011 a 202606)

---

## Anomalias encontradas

### 68 registros com `Municipio_Ibge` nulo

Exatamente 1 registro nulo por mês em `Municipio_Ibge`, `Estado_Ibge` e `Sigla_Regiao`. Provável agregado ou registro de "não identificado" publicado mensalmente pelo BCB. **Tratamento: descartar no parse** — não são registros municipais.

### 97 combinações município-mês faltando

De 378.828 combinações esperadas (5.571 × 68), existem 378.731 reais — 97 faltando. Concentrados nos meses iniciais do PIX, quando parte dos municípios ainda não tinha atividade registrada. **Tratamento: ausência de registro = sem atividade naquele mês**, não erro de pipeline.

### `Municipio_Ibge` e `Estado_Ibge` chegam como `float64`

Consequência dos nulos: o pandas infere `float` quando há `None` em coluna de inteiros. O cast para `int` deve acontecer no Pydantic, após descartar os registros nulos.

---

## Gap temporal com Olist

Olist cobre 2015–2018. PIX foi lançado em novembro/2020. **Não há sobreposição temporal direta.**

O PIX será usado como **covariável de perfil municipal** — representando o nível de digitalização financeira do município — e não como série temporal alinhada com os pedidos Olist. A agregação recomendada é média mensal por município sobre o período disponível (2020+).

---

## Decisões para a spec

1. `DataBase='202011'` fixo no código — captura a série completa desde o lançamento
2. Registros com `Municipio_Ibge` nulo descartados no parse
3. `Municipio_Ibge` e `Estado_Ibge` convertidos de `float` para `int` no Pydantic
4. Volume mínimo esperado: 378.000 registros (folga para crescimento da série)
5. Sem paginação — uma única chamada GET com timeout de 120s
