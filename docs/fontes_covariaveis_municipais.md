# Fontes de Dados — Covariáveis Municipais
## Projeto: Geo Analytics Platform

> Documento de referência de fontes públicas para construção de covariáveis por município.
> Status de cada fonte reflete o escopo congelado da v1 e o roadmap de evoluções futuras.

---

## Mapa de Status

| Fonte | Status | Versão |
|---|---|---|
| **IBGE — Localidades** | ✅ v1 — Escopo congelado | v1 |
| **IBGE — Censo 2022 (SIDRA)** | ✅ v1 — Escopo congelado | v1 |
| **BCB — PIX por Município** | ✅ v1 — Escopo congelado | v1 |
| MTE — CAGED | 🔵 v2 — Confirmado | v2 |
| MTE — RAIS | 🔵 v2 — Confirmado | v2 |
| BCB — IFData | 🟡 v2 — Candidato | v2 |
| Anatel — SCM Banda Larga | 🟡 v2 — Candidato | v2 |
| IBGE — Malhas Geográficas | 🟡 v2 — Candidato | v2 |
| PNAD Contínua TIC | ⚪ Backlog | — |
| PNAD Contínua Mercado de Trabalho | ⚪ Backlog | — |
| BCB — SGS (séries macro) | ⚪ Backlog | — |
| BCB — Expectativas de Mercado | ⚪ Backlog | — |
| Anatel — Cobertura Móvel | ⚪ Backlog | — |
| CGI.br — TIC Domicílios | ❌ Descartada | — |
| Febraban — Tec. Bancária | ❌ Descartada | — |
| IBGE — POF | ❌ Descartada | — |

---

## v1 — Escopo Congelado

> Estas três fontes compõem o conjunto fixo de covariáveis da v1.
> Nenhuma outra fonte de covariável entra na v1. Sem exceção.

---

### IBGE — Localidades (API de Municípios)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Geográfico / Referencial |
| **Forma de consumo** | API REST |
| **Granularidade** | Município |
| **Periodicidade** | Estável (base de referência) |
| **Formato** | JSON |
| **Endpoint** | `https://servicodados.ibge.gov.br/api/v1/localidades/municipios` |

**Resumo:** API referencial que retorna todos os municípios brasileiros com código IBGE, nome, microrregião, mesorregião, UF e região. Tabela-chave para joins entre todas as demais fontes. É o ponto de entrada obrigatório de qualquer pipeline que use código IBGE como chave de município.

---

### IBGE — Censo Demográfico 2022 (SIDRA)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Demográfico / Socioeconômico |
| **Forma de consumo** | API REST (SIDRA) |
| **Granularidade** | Município (cobertura completa — 5.570 municípios) |
| **Periodicidade** | Decenal (referência 2022) |
| **Formato** | JSON |
| **Endpoint** | `https://apisidra.ibge.gov.br/values/` |
| **Documentação** | `https://servicodados.ibge.gov.br/api/docs/agregados?versao=3` |

**Resumo:** Base demográfica de referência com cobertura para todos os 5.570 municípios. Contém renda domiciliar per capita, escolaridade, estrutura etária, acesso declarado à internet, tipo de domicílio. É a fundação demográfica do modelo de matching — sem ela não há como garantir que tratamento e controle são comparáveis.

**Tabelas-chave no SIDRA:**
- `9606` — Domicílios com internet por município
- `9605` — Rendimento médio domiciliar per capita
- `9514` — População por sexo e faixa etária

---

### BCB — PIX por Município (TransacoesPorMunicipio)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Pagamento Digital |
| **Forma de consumo** | API REST / OData |
| **Granularidade** | Município |
| **Periodicidade** | Mensal |
| **Formato** | JSON (OData) |
| **Endpoint** | `https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata/TransacoesPorMunicipio` |
| **Documentação** | `https://dadosabertos.bcb.gov.br/dataset/pix` |

**Resumo:** Quantidade e volume financeiro de transações PIX por município e tipo de pessoa (PF e PJ). Sinal direto de adoção de pagamento digital — a covariável mais relevante para um experimento de produto digital de e-commerce. Série histórica disponível a partir de 2020.

**Nota de gap temporal:** Os dados do Olist cobrem 2015–2018. O PIX só existe a partir de 2020. Esse gap será documentado nas premissas do intermediate — o PIX entra como covariável de perfil municipal atual, não como covariável do período do experimento.

---

## v2 — Confirmados

> Fontes bem mapeadas tecnicamente. Entram na v2 após a v1 estar em produção.

---

### MTE — CAGED (Novo CAGED)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Socioeconômico / Atividade Econômica |
| **Forma de consumo** | Base dos Dados — `basedosdados.br_me_caged.microdados_movimentacao` |
| **Granularidade** | Município |
| **Periodicidade** | Mensal |
| **Formato** | BigQuery público (via Base dos Dados) |

**Resumo:** Microdados de movimentações mensais de emprego formal — admissões e desligamentos por município, setor CNAE, faixa salarial e escolaridade. Proxy de dinamismo econômico local e capacidade de consumo. Acesso via Base dos Dados elimina o problema de download de CSV compactado.

---

### MTE — RAIS

| Atributo | Detalhe |
|---|---|
| **Domínio** | Socioeconômico / Atividade Econômica |
| **Forma de consumo** | Base dos Dados — `basedosdados.br_me_rais.microdados_vinculos` |
| **Granularidade** | Município |
| **Periodicidade** | Anual |
| **Formato** | BigQuery público (via Base dos Dados) |

**Resumo:** Estoque de vínculos formais de emprego por município, setor econômico (CNAE), faixa salarial e escolaridade. Complementa o CAGED com visão de estoque anual. Proxy de formalidade econômica — municípios com maior participação de serviços e tecnologia tendem a ter maior adoção digital.

---

## v2 — Candidatos

> Fontes com potencial confirmado mas sem prioridade explícita na v2. Status mantido do ciclo anterior.

---

### BCB — IFData (Dados Financeiros por Município)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Financeiro |
| **Forma de consumo** | API REST / OData |
| **Granularidade** | Município |
| **Periodicidade** | Trimestral |
| **Formato** | JSON (OData) |
| **Endpoint** | `https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v3/odata/` |

**Resumo:** Crédito concedido, depósitos, número de clientes ativos por município. Permite construir índice de densidade financeira e bancarização municipal. Complementa o PIX com dimensão de crédito e estrutura bancária.

---

### Anatel — Acessos SCM (Banda Larga Fixa)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Infraestrutura Digital |
| **Forma de consumo** | Download CSV |
| **Granularidade** | Município |
| **Periodicidade** | Mensal |
| **Formato** | CSV (~200MB por competência) |
| **URL** | `https://dados.gov.br` → pesquisar "acessos SCM" |

**Resumo:** Quantidade de acessos de banda larga fixa por município, operadora e tecnologia. Principal proxy de penetração de internet fixa no nível municipal. Ressalva: CSV de ~200MB por competência — requer pipeline de ingestão mais robusto.

---

### IBGE — Malhas Geográficas Municipais

| Atributo | Detalhe |
|---|---|
| **Domínio** | Geoespacial |
| **Forma de consumo** | API REST |
| **Granularidade** | Município |
| **Periodicidade** | Estável (atualizado a cada Censo) |
| **Formato** | GeoJSON / TopoJSON |
| **Endpoint** | `https://servicodados.ibge.gov.br/api/v3/malhas/municipios/{codmun}` |

**Resumo:** Polígonos geográficos dos municípios. Necessário para visualizações cartográficas no Streamlit e para joins geoespaciais. Não impacta o matching estatístico — é dependência da camada de visualização.

---

## Backlog

> Fontes de menor prioridade ou com limitações de granularidade. Avaliar oportunisticamente.

---

### IBGE — PNAD Contínua TIC

| Atributo | Detalhe |
|---|---|
| **Domínio** | Infraestrutura Digital / Comportamento |
| **Granularidade** | UF, Regiões Metropolitanas, Capitais |
| **Periodicidade** | Anual |
| **Endpoint** | `https://apisidra.ibge.gov.br/values/` |

**Resumo:** % de domicílios com internet, tipo de conexão, dispositivos utilizados. Não possui desagregação municipal — granularidade máxima é UF. Pode ser usada como proxy de UF para imputação em municípios menores.

---

### IBGE — PNAD Contínua (Mercado de Trabalho e Renda)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Socioeconômico |
| **Granularidade** | UF, 20 Regiões Metropolitanas, Capitais |
| **Periodicidade** | Trimestral e Anual |

**Resumo:** Taxa de desemprego, rendimento médio domiciliar, uso de serviços online. Sem desagregação municipal — o Censo 2022 já cobre essa dimensão com representatividade municipal.

---

### BCB — SGS (Séries Temporais Econômicas)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Macroeconômico / Financeiro |
| **Granularidade** | Brasil (série nacional) |
| **Endpoint** | `https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo}/dados` |

**Resumo:** Selic, IPCA, câmbio, crédito total, inadimplência. Variáveis de controle macroeconômico para modelos com dimensão temporal. Sem desagregação regional.

---

### BCB — Expectativas de Mercado (Focus)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Macroeconômico |
| **Granularidade** | Brasil |
| **Endpoint** | `https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/` |

**Resumo:** Projeções de IPCA, Selic, PIB, câmbio de ~130 instituições financeiras. Variável de controle temporal — sem desagregação regional.

---

### Anatel — Cobertura Móvel (3G/4G/5G)

| Atributo | Detalhe |
|---|---|
| **Domínio** | Infraestrutura Digital |
| **Granularidade** | Geoespacial (polígonos) |
| **Formato** | Shapefile / GeoJSON |
| **URL** | `https://sistemas.anatel.gov.br/se/public/cmap.php` |

**Resumo:** Mapas de cobertura por tecnologia e operadora. Para extrair % de cobertura por município é necessário cruzamento geoespacial com a malha IBGE — requer GeoPandas/PostGIS. Os dados representam cobertura teórica, não experiência real.

---

## Descartadas

### CGI.br — TIC Domicílios e TIC Empresas

**Motivo:** Sem API pública. Sem código IBGE de município — desagregação por "porte de município" não permite join direto. Substituída pelo Censo 2022 (SIDRA) e BCB PIX.

---

### Febraban — Pesquisa de Tecnologia Bancária

**Motivo:** Relatório PDF sem API nem microdados abertos. Dados agregados nacionais sem desagregação regional. Substituída por BCB PIX e BCB IFData com granularidade municipal e acesso via API.

---

### IBGE — POF (Pesquisa de Orçamentos Familiares)

**Motivo:** Sem representatividade estatística no nível municipal — apenas UF. Última edição 2017–2018, desatualizada para mensurar adoção digital pós-pandemia.

---

## Endpoints de Referência

```
# IBGE — Localidades
https://servicodados.ibge.gov.br/api/v1/localidades/municipios

# IBGE — SIDRA (Censo 2022)
https://apisidra.ibge.gov.br/values/t/{tabela}/n6/all/v/all/p/last/

# BCB — PIX por Município
https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata/TransacoesPorMunicipio

# BCB — IFData (v2)
https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v3/odata/

# BCB — SGS (backlog)
https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo}/dados?formato=json

# Anatel — SCM (v2)
https://dados.gov.br/dataset/acessos-scm

# Base dos Dados — CAGED (v2)
basedosdados.br_me_caged.microdados_movimentacao

# Base dos Dados — RAIS (v2)
basedosdados.br_me_rais.microdados_vinculos
```

---

*Atualizado: Junho/2026 | Projeto: Geo Analytics Platform*
