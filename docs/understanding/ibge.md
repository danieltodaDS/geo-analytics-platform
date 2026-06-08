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

### Tabelas em uso no pipeline v1

> **Nota:** as tabelas originalmente especificadas (9605, 9606) foram descartadas após validação empírica — ambas retornavam apenas `"População residente"`, não renda nem internet. As tabelas corretas foram identificadas via catálogo SIDRA e verificadas ao vivo.

| Tabela | Conteúdo real | Registros | Linhas/município |
|--------|--------------|-----------|-----------------|
| `9514` | População residente por sexo e faixa etária | 11.140 | 2 |
| `10295` | Rendimento nominal médio e mediano domiciliar per capita | 22.280 | 4 |
| `9936` | % domicílios com conexão à internet (filtrado na URL) | 5.570 | 1 |

### Endpoint padrão (9514 e 10295)

```
GET https://apisidra.ibge.gov.br/values/t/{tabela}/n6/all/v/all/p/last
```

| Segmento | Significado |
|----------|-------------|
| `n6`     | Nível geográfico 6 = Município |
| `all`    | Todos os municípios |
| `v/all`  | Todas as variáveis da tabela |
| `p/last` | Período mais recente disponível (2022 no Censo) |

- Sem autenticação
- Rate limit: respeitar ~0,5s entre chamadas

### Endpoint com filtro de classificação (9936)

A tabela 9936 possui três classificações: existência de internet (ID `2072`), condição de ocupação (ID `63`) e tipo de domicílio (ID `125`). Sem filtros, `v/all/p/last` retorna apenas o "Total" da classificação de internet — que é o total de domicílios, não o subconjunto com conexão.

URL correta para obter `% domicílios com internet = Sim`:

```
GET https://apisidra.ibge.gov.br/values/t/9936/n6/all/v/1000381/p/last/c2072/77585/c63/95826
```

| Filtro | Significado |
|--------|-------------|
| `v/1000381` | Variável: `Domicílios particulares permanentes ocupados — percentual do total geral` |
| `c2072/77585` | Classificação 2072 (existência de internet) = categoria 77585 (Sim) |
| `c63/95826` | Classificação 63 (condição de ocupação) = categoria 95826 (Total) |

Categorias da classificação 2072: `77584` = Total, `77585` = Sim, `77586` = Não.

### Paginação

Não há paginação. Cada tabela retorna todos os municípios em uma única chamada.

### Estrutura da resposta — comportamento especial do `data[0]`

A API retorna uma lista onde **`data[0]` é o mapa de cabeçalho** e `data[1:]` são os registros reais. Todos os itens têm as mesmas chaves internas curtas:

```
NC, NN, MC, MN, V, D1C, D1N, D2C, D2N, D3C, D3N, D4C, D4N, [D5C, D5N, D6C, D6N]
```

Convenção das chaves: sufixo `C` = código, sufixo `N` = nome legível. `NC/NN` = nível territorial, `MC/MN` = unidade de medida, `V` = valor, `D1`–`D6` = dimensões da tabela.

### Schema — `data[0]` observado por tabela

**Tabela 9514 — População por sexo e faixa etária**

```json
{
  "D1C": "Município (Código)",  "D2C": "Variável (Código)",  "D3C": "Ano (Código)",
  "D4C": "Sexo (Código)",       "D5C": "Forma de declaração da idade (Código)",
  "D6C": "Idade (Código)"
}
```

Variáveis retornadas: `93` = `"População residente"`, `1000093` = `"População residente — percentual do total geral"`.
Todas as dimensões (D4–D6) chegam como `"Total"` com `v/all/p/last`.

**Tabela 10295 — Rendimento domiciliar per capita**

```json
{
  "D1C": "Município (Código)",  "D2C": "Variável (Código)",  "D3C": "Ano (Código)",
  "D4C": "Sexo (Código)",       "D5C": "Grupo de idade (Código)",
  "D6C": "Cor ou raça (Código)"
}
```

Variáveis retornadas (4 por município):

| `D2C` | Nome | Unidade |
|-------|------|---------|
| `13604` | Moradores (contagem base) | Pessoas |
| `1013604` | Moradores (% do total) | % |
| `13431` | **Rendimento nominal médio mensal domiciliar per capita** | R$ |
| `13534` | **Rendimento nominal mediano mensal domiciliar per capita** | R$ |

Todas as dimensões (D4–D6) chegam como `"Total"` com `v/all/p/last`. As covariáveis úteis são `13431` e `13534`.

**Tabela 9936 — Domicílios com internet (URL filtrada)**

```json
{
  "D1C": "Município (Código)",  "D2C": "Variável (Código)",  "D3C": "Ano (Código)",
  "D4C": "Existência de conexão domiciliar à Internet (Código)"
}
```

Com o filtro `c2072/77585`: 1 registro por município, D4N = `"Sim"`, V = percentual de domicílios com internet (ex: `87.35` para município 1100015).

### Schema — primeiro registro real observado (município 1100015)

**Tabela 9514:**
```json
{"D1C": "1100015", "D2C": "93", "D2N": "População residente", "D3C": "2022", "D4N": "Total", "D5N": "Total", "D6N": "Total", "V": "21494"}
```

**Tabela 10295 (variável rendimento médio):**
```json
{"D1C": "1100015", "D2C": "13431", "D2N": "Valor do rendimento nominal médio mensal domiciliar per capita...", "D3C": "2022", "D4N": "Total", "D5N": "Total", "D6N": "Total", "V": "1210.60"}
```

**Tabela 9936 (com filtro):**
```json
{"D1C": "1100015", "D2C": "1000381", "D2N": "Domicílios particulares permanentes ocupados — percentual do total geral", "D3C": "2022", "D4N": "Sim", "V": "87.35"}
```

### Observações de tipo

Todos os campos chegam como `string` — incluindo `V` e `D1C`. Cast para tipos corretos ocorre no staging (dbt).

### Chave de join com Localidades

`D1C` = código IBGE do município (string de 7 dígitos). Mesmo valor que `id_municipio` da API de Localidades, mas como string — requer cast para `BIGINT` em ambos os lados antes do join no dbt.

`D1N` concatena UF ao nome (`"Alta Floresta D'Oeste - RO"`) — descartar no pipeline, usar apenas `D1C`.

### Edge cases

- `data[0]` não é registro de dado — se incluído no DataFrame corrompe o schema.
- `V` pode ser `"-"` ou `"..."` para dado suprimido por sigilo estatístico — tratar como `NULL` no staging. Verificado: tabela 9936 tem cobertura 100% (0 NULLs em 5.570 municípios).
- `v/all/p/last` sem filtros retorna apenas dimensões `= "Total"` para 9936 — não traz o breakdown por existência de internet. Filtro de classificação obrigatório na URL (ver seção acima).
- O número de dimensões varia por tabela: 9514 e 10295 têm D4–D6, 9936 filtrada tem apenas D4 na resposta.

---

## 3. Implicações para o Pipeline

- Dois módulos separados: `ibge_localidades.py` e `ibge_censo.py`.
- Ambos fazem chamada única sem loop de paginação — retry com Tenacity simples (sem estado de página).
- `_parse_sidra` deve ser função auxiliar explícita e documentada — o comportamento do `data[0]` é não-óbvio.
- Pydantic schema para SIDRA: `V: Optional[str]` para cobrir supressão (`"-"`, `"..."`).
- URLs por tabela ficam em `_TABELAS_CONFIG` no script — não há URL genérica que funcione para todas as tabelas.
- No staging dbt:
  - `D1C` → `BIGINT` (código município)
  - `V` → `DOUBLE` via `try_cast`
  - `D3C` → `BIGINT` (ano)
- A hierarquia `microrregiao` está disponível na API de Localidades mas não é extraída na v1 — disponível para v2 se necessário.

---

*Explorado em: Junho/2026 | Ref: `exploration/ibge_exploration.ipynb`*
