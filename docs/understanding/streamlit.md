# Understanding — Streamlit Dashboard

> Fase: Feature 9 — Explorar → **Entender**
> Fonte: `exploration/streamlit_exploration.ipynb` + análise dos outputs

---

## Escopo da aba explorada

Aba de matching por Mahalanobis: o usuário seleciona um município e vê os 5 mais similares, com comparativo visual de covariáveis lado a lado.

---

## Cobertura do conjunto de matching

| Métrica | Valor |
|---|---|
| Total de municípios no mart | 3.213 |
| Municípios disponíveis para matching | 2.874 (89,4%) |
| Excluídos por nulo | 339 |

**Causa dos 339 excluídos:** `pct_pagamento_cartao` é derivada de pedidos Olist com método de pagamento informado. Municípios com pedidos mas sem pagamento registrado ficam sem essa covariável e fora do matching.

**Decisão:** exibir aviso na interface quando o município selecionado não está no conjunto de matching. Não tentar imputar — o usuário precisa saber que o par não é confiável.

---

## Qualidade dos pares — validação empírica

Resultado do sanity check com municípios de perfis conhecidos:

| Município | Top 3 pares | Coerência |
|---|---|---|
| São Paulo-SP | Rio de Janeiro, Brasília, Salvador | ✅ maiores metrópoles |
| Rio de Janeiro-RJ | Brasília, Salvador, Fortaleza | ✅ |
| Salvador-BA | Fortaleza (d=0.9), Manaus, BH | ✅ capitais nordestinas/norte |
| Curitiba-PR | Porto Alegre, Goiânia, Recife | ✅ capitais de médio porte |
| Recife-PE | Goiânia, Belém, Curitiba | ✅ |
| Tanque Novo-BA (3 pedidos) | Miraíma-CE, Coronel João Sá-BA, Cajapió-MA | ✅ pequenos do Nordeste |
| Balneário Piçarras-SC (4 pedidos) | Antônio Prado-RS, Lucas do Rio Verde-MT | ✅ pequenos do Sul/Centro-Oeste |

O algoritmo funciona bem em todos os perfis — grandes metrópoles encontram metrópoles, municípios pequenos encontram similares de mesmo porte e região.

---

## Escala de distâncias — problema de interpretação

A distância de Mahalanobis varia muito por perfil de município:

| Município | Dist. top 1 | Dist. top 5 | Dist. mediana |
|---|---|---|---|
| São Paulo | 18.7 | 32.6 | 40.4 |
| Balneário Piçarras | 0.4 | ~0.6 | — |

Mostrar o valor absoluto confunde o usuário: 32.6 para SP é o melhor disponível; 0.5 para um município pequeno é excelente. A interpretação depende do contexto.

**Decisão:** exibir a similaridade como **ratio relativo à mediana** (`ratio = d_match / mediana(todas_as_distâncias_do_município_alvo)`). Quanto menor o ratio, mais próximo do alvo em relação ao universo de opções disponíveis. Complementar com classificação qualitativa (verde / amarelo / vermelho) com thresholds calibrados empiricamente.

---

## Visualização escolhida — Small multiples

Quatro opções avaliadas:

| Opção | Descrição | Problema |
|---|---|---|
| Tabela comparativa | Métricas em linhas, municípios em colunas | Difícil comparar visualmente valores na mesma coluna |
| Barras agrupadas | Todos municípios × todas métricas num gráfico | Escalas incompatíveis distorcem a leitura |
| Radar chart | Perfil normalizado sobreposto | Requer normalização; valor absoluto se perde |
| **Small multiples** | Um gráfico por métrica, escala independente | **Escolhida** |

**Small multiples** é o formato mais honesto: cada covariável tem sua própria escala, o município alvo é destacado em azul escuro, os pares em azul claro. O tomador de decisão lê cada métrica no seu contexto natural.

---

## Métricas exibidas no painel principal

4 das 6 covariáveis de matching — as mais interpretáveis para um tomador de decisão não técnico:

| Covariável | Justificativa |
|---|---|
| `populacao_residente` | Escala do mercado — a mais imediata |
| `renda_media_per_capita` | Poder de compra |
| `pct_domicilios_com_internet` | Infraestrutura digital |
| `penetracao_olist` | Adoção de e-commerce — liga o perfil ao negócio |

`ticket_medio` e `pct_pagamento_cartao` também entram no matching mas não são exibidas no painel principal — ficam disponíveis como detalhe expandível (decisão de UX para a spec).

---

## Decisões confirmadas para a spec

1. Conjunto de matching: `df.dropna(subset=FEATURES)` — sem imputação
2. Matriz de covariância calculada uma vez sobre o conjunto completo
3. Matching com reposição (conforme backlog item 1)
4. k=5 fixo na fase 4a
5. Similaridade exibida como `ratio = d_match / mediana` + classificação qualitativa (não valor absoluto)
6. Visualização: small multiples, 2 colunas × 2 linhas (4 métricas), escala zero-based por gráfico
7. Município alvo destacado visualmente (cor + marcador ★)
8. Aviso quando município não está no conjunto de matching

---

*Atualizado: 2026-06-09*
