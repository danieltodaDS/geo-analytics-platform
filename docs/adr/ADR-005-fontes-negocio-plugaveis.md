# ADR-005: Fontes de Negócio como Categoria Genérica e Plugável

**Status:** Aceito
**Data:** Junho/2026

---

## Decisão

Tratar as fontes de negócio como uma **categoria genérica e plugável**, não como uma fonte específica. O pipeline é projetado para receber qualquer dataset de e-commerce com granularidade municipalizável — não apenas o Olist.

## Contexto

A v1 usa o Olist (Kaggle) como única fonte de negócio. A decisão é: o pipeline deve ser construído para o Olist especificamente, ou para a categoria "fonte de negócio com pedidos municipalizáveis"?

## Justificativa

- O problema de negócio é genérico — medir causalidade em expansão geográfica de produto digital. Amarrar a plataforma ao Olist reduz o argumento de portfólio a "análise do Olist", não a "plataforma de Geo Analytics"
- Qualquer fonte histórica com `(municipio_id, data, valor)` pode alimentar o experimento — a abstração tem custo baixo e benefício alto
- A separação explícita entre fontes de negócio e covariáveis municipais é a decisão arquitetural central do projeto: covariáveis descrevem o contexto, fontes de negócio descrevem o que medir

## Consequências arquiteturais

```
Staging:      resolve o problema específico de cada fonte
              (ex: geocodificação CEP → município_id para o Olist)

Intermediate: padroniza todas as fontes para schema comum:
              municipio_id | ano_mes | total_pedidos | receita_total | ticket_medio | fonte

A partir do intermediate: pipeline agnóstico à fonte de negócio
```

- Cada fonte de negócio tem seu próprio modelo de staging com lógica de geocodificação documentada na spec correspondente
- O intermediate é o ponto de convergência — a partir dele, Olist e qualquer futura fonte são indistinguíveis
- Premissas de integração (ex: gap temporal entre Olist 2015–2018 e PIX 2020+) são documentadas por fonte na spec, não hard-codadas no pipeline

## Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| Olist como fonte única e hard-coded | Reduz reusabilidade; limita o argumento de portfólio |
| Schema livre até o mart | Inviabiliza a construção agnóstica do experimento causal |
