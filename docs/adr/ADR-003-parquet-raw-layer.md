# ADR-003: Parquet como Formato da Raw Layer

**Status:** Aceito
**Data:** Junho/2026

---

## Decisão

Parquet com compressão Snappy como formato padrão da raw layer no GCS. JSONL como fallback exclusivo para fontes com schema variável ou não-estruturado.

## Contexto

A raw layer precisa de um formato que:
- Preserve tipos nativos (int, float, string, date) sem ambiguidade
- Seja carregável diretamente no BigQuery sem transformação
- Tenha boa compressão para minimizar custo de storage no GCS
- Suporte leitura colunar eficiente para queries no BigQuery

## Justificativa

- **Preserva tipos** — `id_municipio` chega como `int` no Parquet; chega como `"1100015"` no CSV, exigindo cast no staging e criando risco de erro silencioso
- **Colunar** — BigQuery lê apenas as colunas consultadas; queries que acessam 3 de 16 colunas pagam por 3, não por 16
- **Compressão eficiente** — Snappy reduz tamanho típico em 3–5×  vs CSV, com decompressão rápida
- **Suporte nativo no BigQuery** — `bq load --source_format=PARQUET` sem opções adicionais
- **Schema embarcado** — o Parquet carrega o schema junto com os dados; o BigQuery infere colunas e tipos automaticamente

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| CSV | Sem tipos nativos; problemas com encoding UTF-8, vírgulas em campos, separadores — todas fontes brasileiras têm acentos |
| JSON (linha por linha) | Sem compressão nativa; BigQuery cobra pelo scan do JSON completo, não colunar |
| Avro | Ótimo para streaming com schema registry; overhead desnecessário para batch simples |
| ORC | Alternativa válida, mas Parquet tem suporte mais amplo no ecossistema Python (pandas, pyarrow) |

## Consequências

- JSONL como fallback documentado para casos edge — nenhuma fonte da v1 usa JSONL
- Scripts de ingestão dependem de `pyarrow` ou `pandas` para escrita — adicionados ao `requirements.txt`
- Particionamento Hive-style no path: `raw/{fonte}/year=X/month=X/day=X/data.parquet` — BigQuery detecta automaticamente as partições
