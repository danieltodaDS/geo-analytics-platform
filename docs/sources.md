# Sources — SLA, Frequência e Tolerância

> Documento de referência operacional para todas as fontes de dados da v1.
> Define o contrato de disponibilidade esperado de cada fonte e o comportamento do pipeline em caso de violação.

---

## Resumo

| Fonte | Frequência | SLA | Tolerância | Status v1 |
|---|---|---|---|---|
| Olist (Kaggle) | Batch única | — | — | ✅ Ativo |
| IBGE — Localidades | Estável | — | — | ✅ Ativo |
| IBGE — Censo 2022 (SIDRA) | Decenal | — | — | ✅ Ativo |
| BCB — PIX por Município | Mensal | Dia 15 do mês seguinte | 3 dias | ✅ Ativo |

---

## Olist (Kaggle)

| Atributo | Detalhe |
|---|---|
| **Tipo** | Dataset histórico estático |
| **Forma de acesso** | Kaggle API — download de CSV |
| **Frequência de atualização** | Sem atualização — dataset congelado em 2018 |
| **Período coberto** | 2015–2018 |
| **SLA** | Não aplicável — carga batch única |
| **Tolerância** | Não aplicável |
| **Owner no pipeline** | `ingestion/src/olist.py` |
| **Raw path** | `raw/olist/year=X/month=X/day=X/data.parquet` |

**Nota de gap temporal:** Os dados cobrem 2015–2018. As covariáveis municipais têm referências mais recentes (Censo 2022, PIX 2020+). Esse gap é uma premissa documentada — covariáveis entram como perfil municipal atual, não como variáveis do período do experimento.

**Comportamento em falha:** Download via Kaggle API pode falhar por credenciais expiradas ou mudança de nome do dataset. Script deve logar erro com instrução de renovação e encerrar — não há retry útil neste caso.

---

## IBGE — Localidades

| Atributo | Detalhe |
|---|---|
| **Tipo** | API REST pública |
| **Endpoint** | `https://servicodados.ibge.gov.br/api/v1/localidades/municipios` |
| **Frequência de atualização** | Estável — atualizada a cada alteração oficial de divisão municipal |
| **Período coberto** | Referência atual (sem série histórica) |
| **SLA** | Não aplicável — base de referência, não série temporal |
| **Tolerância** | Não aplicável |
| **Owner no pipeline** | `ingestion/src/ibge_localidades.py` |
| **Raw path** | `raw/ibge_localidades/year=X/month=X/day=X/data.parquet` |

**Freshness dbt:**
```yaml
freshness:
  warn_after: {count: 90, period: day}
  error_after: {count: 180, period: day}
```
Base estável — freshnesse longa é esperada e normal.

**Comportamento em falha:** API pública sem autenticação — falha indica instabilidade do serviço IBGE. Retry com Tenacity (3 tentativas, backoff exponencial). Após esgotamento: logar erro e encerrar.

---

## IBGE — Censo 2022 (SIDRA)

| Atributo | Detalhe |
|---|---|
| **Tipo** | API REST pública (SIDRA) |
| **Endpoint** | `https://apisidra.ibge.gov.br/values/t/{tabela}/n6/all/v/all/p/last` |
| **Tabelas** | 9606 (internet), 9605 (renda), 9514 (população) |
| **Frequência de atualização** | Decenal — próxima atualização esperada ~2032 |
| **Período coberto** | Censo 2022 |
| **SLA** | Não aplicável — referência decenal |
| **Tolerância** | Não aplicável |
| **Owner no pipeline** | `ingestion/src/ibge_censo.py` |
| **Raw paths** | `raw/ibge_censo_9606/...`, `raw/ibge_censo_9605/...`, `raw/ibge_censo_9514/...` |

**Freshness dbt:**
```yaml
freshness:
  warn_after: {count: 90, period: day}
  error_after: {count: 180, period: day}
```

**Comportamento em falha:** Mesma lógica de retry que Localidades. Rate limit da API SIDRA: aguardar 0,5s entre chamadas de tabelas distintas.

---

## BCB — PIX por Município

| Atributo | Detalhe |
|---|---|
| **Tipo** | API REST OData pública |
| **Endpoint** | `https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata/TransacoesPorMunicipio` |
| **Frequência de atualização** | Mensal |
| **Período coberto** | A partir de novembro/2020 |
| **SLA** | Dia 15 do mês seguinte ao período de referência |
| **Tolerância** | 3 dias corridos após o SLA (dia 18) |
| **Owner no pipeline** | `ingestion/src/bcb_pix.py` |
| **Raw path** | `raw/bcb_pix/year=X/month=X/day=X/data.parquet` |

**Freshness dbt:**
```yaml
freshness:
  warn_after:  {count: 1, period: day}
  error_after: {count: 3, period: day}
```

**Comportamento em falha:**
- Retry com Tenacity em erros 5xx e timeout
- Se dado do mês corrente ainda não disponível (HTTP 200 com 0 registros): logar warning e não gravar arquivo — evitar Parquet vazio na raw layer
- Se SLA ultrapassado em mais de 3 dias: disparar alerta (Elementary ou GitHub Actions)

**Nota de gap temporal:** PIX existe a partir de 2020. Dados Olist cobrem 2015–2018. O PIX entra como covariável de perfil municipal atual — sinal de adoção de pagamento digital hoje — não como variável do período do experimento.

---

## Política de Freshness — Resumo dbt

```yaml
# sources.yml — aplicar por source conforme tabela acima

version: 2

sources:
  - name: ibge_localidades
    freshness:
      warn_after:  {count: 90,  period: day}
      error_after: {count: 180, period: day}

  - name: ibge_censo
    freshness:
      warn_after:  {count: 90,  period: day}
      error_after: {count: 180, period: day}

  - name: bcb_pix
    freshness:
      warn_after:  {count: 1, period: day}
      error_after: {count: 3, period: day}

  - name: olist
    # Sem freshness — carga batch única, não há atualização esperada
```

---

*Atualizado: Junho/2026*
