# ADR-011: Ingestão Event-Driven do Olist via Cloud Function + Landing Bucket

**Status:** Aceito  
**Data:** Junho/2026  
**Impacta:** [ADR-003](ADR-003-parquet-raw-layer.md), [ADR-006](ADR-006-makefile-orquestracao-local.md), [ADR-009](ADR-009-github-actions-ingestao-remota.md)

---

## Decisão

Introduzir um bucket de entrada (`geo-analytics-platform-landing`) e uma Cloud Function acionada por evento de finalização de objeto no GCS. Quando o arquivo CSV do Olist é depositado no bucket de entrada, a função executa o script de ingestão (validação Pydantic + conversão para Parquet) e grava o resultado no bucket oficial de raw (`geo-analytics-platform-raw`). O comando `make olist-upload` passa a copiar os CSVs para o bucket de entrada, não mais para o bucket oficial diretamente.

---

## Contexto

O fluxo atual exige uma etapa manual invisível antes de qualquer uso do repositório:

```
clone repo → ??? baixar Kaggle manualmente → colocar em data/raw/ → make olist-upload
```

Quem clona o repositório precisa saber onde obter os arquivos, qual diretório usar, e em que formato. Essa dependência não está documentada no código — está implícita na convenção local da máquina do desenvolvedor.

Além disso, o `make olist-upload` copia os Parquets diretamente para o bucket oficial sem passar pelo script de ingestão — o que significa que um arquivo malformado ou incompleto pode ser promovido para a raw layer sem nenhuma validação. A validação Pydantic existente em `ingestion/src/olist.py` só é executada quando o script roda localmente, não no caminho de upload remoto.

O Olist é um dataset estático (Kaggle, batch único). Por isso, o padrão event-driven não tem valor operacional de automação — mas resolve dois problemas reais: (1) elimina a etapa manual invisível, tornando o repositório autossuficiente; (2) fecha a lacuna de validação no caminho de upload remoto. Como POC de portfólio, demonstra o padrão event-driven real usado em pipelines de ingestão ad-hoc em produção.

---

## Justificativa

**Repositório autossuficiente:**  
Após a mudança, quem clona o repositório precisa apenas de ADC e de um único comando:

```bash
gcloud storage cp olist_*.csv gs://geo-analytics-platform-landing/olist/
```

Nenhum conhecimento sobre diretório local, formato de arquivo ou sequência de scripts é necessário.

**Validação no caminho remoto:**  
A Cloud Function executa `ingestion/src/olist.py` — o mesmo script usado localmente. A validação Pydantic passa a ser obrigatória no path de upload, não opcional.

**Separação de responsabilidades:**  
O bucket de entrada é zona não-curada — recebe qualquer arquivo. O bucket oficial de raw só recebe dados que passaram pela validação. Essa separação é o padrão de data lake com camada de quarentena.

---

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| Manter `make olist-upload` atual | Mantém a etapa invisível de preparação local; sem validação no caminho remoto |
| Eventarc + Cloud Run | Overhead de containerização desnecessário para um script Python simples; Cloud Function é suficiente para o volume e a complexidade do Olist |
| Documentar o passo manual no README | Resolve a descobribilidade, não o problema de validação ausente no caminho remoto; o fluxo continua com etapa manual |

---

## Consequências

**Nova infraestrutura:**
- Bucket `geo-analytics-platform-landing` — zona de entrada, privado; acesso de escrita restrito a principals com ADC do projeto (sem acesso público ou `allAuthenticatedUsers`)
- Cloud Function `olist-ingest-trigger` — trigger `google.cloud.storage.object.v1.finalized`, runtime Python 3.11
- Service account da função com roles mínimas: `roles/storage.objectViewer` no bucket de entrada, `roles/storage.objectCreator` no bucket oficial de raw — sem `storage.admin` ou roles mais amplas

**`make olist-upload` (ADR-006 — impacto):**
- O target passa a copiar CSVs para o bucket de entrada, não para o bucket oficial
- O Makefile documenta que a conversão para Parquet é responsabilidade da Cloud Function

**Ingestão remota (ADR-009 — impacto):**
- A tabela de frequência de ingestão por fonte é atualizada: Olist passa de "trigger manual via make → raw bucket" para "trigger manual via make → landing bucket → Cloud Function → raw bucket"
- GitHub Actions (`ingest.yml`) não cobre o Olist — a Cloud Function é o mecanismo de ingestão para essa fonte

**Formato da raw layer (ADR-003 — impacto):**
- O path e o formato Parquet + Snappy + `ingestion_date` permanecem inalterados
- O mecanismo de escrita muda: Cloud Function em vez de `gcloud storage cp` direto

**Comportamento de erro na Cloud Function:**
- Validação Pydantic falha ou arquivo inválido: logar o erro via Cloud Logging e não gravar no bucket oficial — o arquivo permanece no bucket de entrada para inspeção manual
- Nenhuma lógica de retry automático na v1: re-upload ao bucket de entrada é o mecanismo de reprocessamento
