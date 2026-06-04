# Entendimento — IBGE (Feature 2)

> Documento baseado na saída real da exploração em `exploration/ibge_exploration.ipynb`.
> Schema verificado via JSON bruto — não inferido do código de parsing.

---

## 1. IBGE Localidades

### Endpoint

```
GET https://servicodados.ibge.gov.br/api/v1/localidades/municipios
```

- Sem autenticação
- Sem parâmetros obrigatórios
- Timeout recomendado: 30s

### Paginação

Não há paginação. A chamada retorna todos os municípios em uma única resposta.

### Volume

**5.571 municípios** retornados (list de dicts).

### Schema — JSON bruto completo (primeiro item observado)

```json
{
  "id": 1100015,
  "nome": "Alta Floresta D'Oeste",
  "microrregiao": {
    "id": 11006,
    "nome": "Cacoal",
    "mesorregiao": {
      "id": 1102,
      "nome": "Leste Rondoniense",
      "UF": {
        "id": 11,
        "sigla": "RO",
        "nome": "Rondônia",
        "regiao": {
          "id": 1,
          "sigla": "N",
          "nome": "Norte"
        }
      }
    }
  },
  "regiao-imediata": {
    "id": 110005,
    "nome": "Cacoal",
    "regiao-intermediaria": {
      "id": 1102,
      "nome": "Ji-Paraná",
      "UF": {
        "id": 11,
        "sigla": "RO",
        "nome": "Rondônia",
        "regiao": {
          "id": 1,
          "sigla": "N",
          "nome": "Norte"
        }
      }
    }
  }
}
```

### Duas hierarquias geográficas paralelas

A API retorna duas divisões geográficas do IBGE side-by-side:

| Hierarquia | Chave raiz | Divisão |
|---|---|---|
| Antiga (até 2017) | `microrregiao` | microrregião → mesorregião → UF → região |
| Nova (desde 2017) | `regiao-imediata` | região imediata → região intermediária → UF → região |

O notebook usou apenas `regiao-imediata`. A `microrregiao` está disponível e pode ser útil para joins com fontes que ainda usam a divisão antiga.

### Campos de nível 1

```
id, nome, microrregiao, regiao-imediata
```

As chaves com hífen (`regiao-imediata`, `regiao-intermediaria`) exigem acesso via `["regiao-imediata"]` em Python — não funcionam como atributo.

### Schema — campos extraídos pelo notebook (pipeline v1)

| Campo pipeline         | Caminho no JSON                                                               | Tipo |
|------------------------|-------------------------------------------------------------------------------|------|
| `id_municipio`         | `m["id"]`                                                                     | int  |
| `nome_municipio`       | `m["nome"]`                                                                   | str  |
| `uf_sigla`             | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["sigla"]`                 | str  |
| `uf_nome`              | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["nome"]`                  | str  |
| `regiao_imediata_id`   | `m["regiao-imediata"]["id"]`                                                  | int  |
| `regiao_imediata_nome` | `m["regiao-imediata"]["nome"]`                                                | str  |
| `regiao_interm_id`     | `m["regiao-imediata"]["regiao-intermediaria"]["id"]`                          | int  |
| `regiao_interm_nome`   | `m["regiao-imediata"]["regiao-intermediaria"]["nome"]`                        | str  |
| `macroregiao_sigla`    | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["regiao"]["sigla"]`       | str  |
| `macroregiao_nome`     | `m["regiao-imediata"]["regiao-intermediaria"]["UF"]["regiao"]["nome"]`        | str  |

Campos disponíveis mas não extraídos na v1: `microrregiao.*`, `mesorregiao.*`, `UF.id`, `regiao.id`.

### Chave de join

`id_municipio` (int, 7 dígitos) — chave primária e ponto de join com todas as demais fontes.

### Edge cases

- Nenhum município veio sem `regiao-imediata` na exploração — hierarquia completa.
- Chaves com hífen no JSON exigem acesso por string literal em Python.

---

## 2. IBGE Censo 2022 — SIDRA

### Endpoint padrão

```
GET https://apisidra.ibge.gov.br/values/t/{tabela}/n6/all/v/all/p/last
```

| Segmento | Significado                                      |
|----------|--------------------------------------------------|
| `n6`     | Nível geográfico 6 = Município                   |
| `all`    | Todos os municípios                              |
| `v/all`  | Todas as variáveis da tabela                     |
| `p/last` | Período mais recente disponível (2022 no Censo)  |

- Sem autenticação
- Rate limit: respeitar ~0,5s entre chamadas

### Paginação

Não há paginação. Cada tabela retorna todos os municípios em uma única chamada.

### Estrutura da resposta — comportamento especial do `data[0]`

A API retorna uma lista onde **`data[0]` é o mapa de cabeçalho** e `data[1:]` são os registros reais. Todos os itens têm as mesmas chaves internas curtas:

```
NC, NN, MC, MN, V, D1C, D1N, D2C, D2N, D3C, D3N, D4C, D4N, [D5C, D5N, D6C, D6N]
```

Convenção das chaves: sufixo `C` = código, sufixo `N` = nome legível. `NC/NN` = nível territorial, `MC/MN` = unidade de medida, `V` = valor, `D1`–`D6` = dimensões da tabela.

### Volume

| Tabela | Total retornado | Registros reais |
|--------|----------------|-----------------|
| 9606   | 11.141 itens   | 11.140 (− 1 cabeçalho) |
| 9605   | 11.141 itens   | 11.140 (− 1 cabeçalho) |
| 9514   | 11.141 itens   | 11.140 (− 1 cabeçalho) |

11.140 registros = 2 linhas por município (5.570 municípios × 2 — `v/all` traz pelo menos dois valores de variável por município).

### Schema — `data[0]` observado por tabela

**Tabela 9606 — Domicilios_com_internet**

```json
{
  "NC": "Nível Territorial (Código)",
  "NN": "Nível Territorial",
  "MC": "Unidade de Medida (Código)",
  "MN": "Unidade de Medida",
  "V":  "Valor",
  "D1C": "Município (Código)",
  "D1N": "Município",
  "D2C": "Variável (Código)",
  "D2N": "Variável",
  "D3C": "Ano (Código)",
  "D3N": "Ano",
  "D4C": "Sexo (Código)",
  "D4N": "Sexo",
  "D5C": "Cor ou raça (Código)",
  "D5N": "Cor ou raça",
  "D6C": "Idade (Código)",
  "D6N": "Idade"
}
```

**Tabela 9605 — Rendimento_medio_domiciliar_percapita**

```json
{
  "NC": "Nível Territorial (Código)",
  "NN": "Nível Territorial",
  "MC": "Unidade de Medida (Código)",
  "MN": "Unidade de Medida",
  "V":  "Valor",
  "D1C": "Município (Código)",
  "D1N": "Município",
  "D2C": "Variável (Código)",
  "D2N": "Variável",
  "D3C": "Ano (Código)",
  "D3N": "Ano",
  "D4C": "Cor ou raça (Código)",
  "D4N": "Cor ou raça"
}
```

Apenas 4 dimensões (D1–D4) — sem Sexo nem Idade.

**Tabela 9514 — Populacao_sexo_faixa_etaria**

```json
{
  "NC": "Nível Territorial (Código)",
  "NN": "Nível Territorial",
  "MC": "Unidade de Medida (Código)",
  "MN": "Unidade de Medida",
  "V":  "Valor",
  "D1C": "Município (Código)",
  "D1N": "Município",
  "D2C": "Variável (Código)",
  "D2N": "Variável",
  "D3C": "Ano (Código)",
  "D3N": "Ano",
  "D4C": "Sexo (Código)",
  "D4N": "Sexo",
  "D5C": "Forma de declaração da idade (Código)",
  "D5N": "Forma de declaração da idade",
  "D6C": "Idade (Código)",
  "D6N": "Idade"
}
```

### Schema — `data[1]` observado (primeiro registro real, chaves internas)

Todas as tabelas retornam o mesmo primeiro registro (município 1100015), os valores diferem apenas nas dimensões de breakdown:

```json
{
  "NC": "6",
  "NN": "Município",
  "MC": "45",
  "MN": "Pessoas",
  "V":  "21494",
  "D1C": "1100015",
  "D1N": "Alta Floresta D'Oeste - RO",
  "D2C": "93",
  "D2N": "População residente",
  "D3C": "2022",
  "D3N": "2022",
  ...
}
```

### Observações de tipo

Todos os campos chegam como `string` — incluindo `V` (valor), `D1C` (código do município) e os demais códigos. Cast para tipos corretos deve ocorrer no staging (dbt).

### Chave de join com Localidades

`D1C` = código IBGE do município (string de 7 dígitos). Mesmo valor que `id_municipio` da API de Localidades, mas como string — requer cast para `INT64` em ambos os lados antes do join no dbt.

O campo `D1N` concatena UF ao nome (`"Alta Floresta D'Oeste - RO"`) — descartar no pipeline, usar apenas `D1C`.

### Edge cases

- `data[0]` não é registro de dado — se incluído no DataFrame, a primeira linha conterá nomes de colunas como valores, corrompendo o schema.
- `V` pode ser `"-"` ou `"..."` para municípios com dado suprimido por sigilo estatístico — tratar como `NULL` no staging.
- O número de dimensões varia por tabela (9605 tem 4, 9606 e 9514 têm 6) — o `_parse_sidra` genérico funciona porque lê as chaves de `data[0]` dinamicamente.

---

## 3. Implicações para a Spec

- Dois módulos separados: `ibge_localidades.py` e `ibge_censo.py`.
- Ambos fazem chamada única sem loop de paginação — retry com Tenacity simples (sem estado de página).
- `_parse_sidra` deve ser função auxiliar explícita e documentada — o comportamento do `data[0]` é não-óbvio.
- Pydantic schema para SIDRA: `V: Optional[str]` para cobrir supressão (`"-"`, `"..."`).
- No staging dbt:
  - `D1C` → `INT64` (código município)
  - `V` → `FLOAT64` com `NULLIF(V, '-')` e `NULLIF(V, '...')`
  - `D3C` → `INT64` (ano)
- A hierarquia `microrregiao` está disponível na API de Localidades mas não é extraída na v1 — documentar como campo disponível para v2 se necessário.

---

*Explorado em: Junho/2026 | Ref: `exploration/ibge_exploration.ipynb`*
