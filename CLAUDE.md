## Sobre o projeto
Pipeline de Analytics Engineering para Geo Lift
usando dados públicos brasileiros no GCP.

## Ciclo de desenvolvimento
Toda feature de produção segue: Explorar → Entender → Especificar → Produtizar.
A produtização segue três fases progressivas — nunca pule etapas:
  4a. Local A — Parquet em data/raw/ local (ADR-003); dbt roda via dbt-duckdb (ADR-007); Streamlit como protótipo local contra DuckDB
  4b. Local B — Parquet local inalterado; dbt migrado para dbt-bigquery (ADR-001); Streamlit contra BigQuery
  4c. Remoto  — GitHub Actions + GCS + BigQuery em produção (ADR-009)
Antes de gerar código de produção, leia a spec correspondente em /specs.

## Arquitetura de contexto
Cada etapa do ciclo produz artefatos específicos que alimentam a próxima:

  Explorar    → exploration/         (notebooks — gitignored, só local)
  Entender    → docs/understanding/  (schema real verificado, anomalias, decisões de fonte)
  Especificar → specs/               (contrato de implementação — lido antes do código)
  Produtizar  → código + testes

Transversais ao ciclo — lidos conforme gatilhos em "Documentos normativos":
  docs/adr/           — decisões arquiteturais (por que, não o quê)
  docs/normative/     — regras obrigatórias (conventions, data_quality)
  docs/roadmap.md     — escopo, sequência de construção e fases futuras
  docs/session_log.md — estado atual e próximo passo

## Stack
Python 3.11, dbt Core, BigQuery, GCS, Streamlit, GitHub Actions

## Ambiente e pacotes
- Gerenciador de ambiente e dependências: **uv**
- Instalar pacote: `uv add <pacote>`
- Instalar dependência de dev: `uv add --dev <pacote>`
- Rodar script: `uv run python <script>`
- Rodar testes: `uv run pytest`
- Sincronizar ambiente: `uv sync`
- **Nunca usar `pip install` diretamente** — sempre `uv add`

## Restrições críticas
- Nunca hardcodar credenciais — variáveis de ambiente obrigatórias; credenciais não entram em código, logs ou commits
- Commits atômicos — um commit por unidade lógica; nunca agrupar etapas distintas do ciclo Explorar/Entender/Especificar/Produtizar
- Regras completas: `docs/normative/conventions.md` e `docs/normative/data_quality.md`

## Documentos normativos
Leia o documento correspondente **antes** de agir — não depois.

- `docs/roadmap.md` — ao iniciar trabalho em qualquer feature nova ou fase nova
- `docs/normative/conventions.md` — ao criar qualquer arquivo Python, modelo dbt, coluna, dataset ou variável de ambiente
- `docs/normative/data_quality.md` — ao escrever qualquer modelo dbt, teste ou sources.yml
- `docs/adr/` — ao implementar ou modificar componente coberto por uma ADR, leia a ADR antes de escrever código:
  - Scripts de ingestão e raw layer → ADR-003, ADR-005
  - Orquestração local / Makefile → ADR-006
  - dbt local (dbt-duckdb, fase 4a) → ADR-007
  - dbt staging → ADR-008
  - Fase remota / CI/CD → ADR-009
  - Warehouse → ADR-001

## Agentes

### Agente 1 — Executor
Perfil de IC Sênior de Dados. Responsável por executar as tarefas do projeto: construção de pipelines, modelagem dimensional, transformações dbt, consultas SQL, scripts Python, e qualquer tarefa técnica solicitada.
- Ao iniciar qualquer sessão, leia `docs/session_log.md` antes de qualquer coisa.
- Ao final de cada sessão, atualize `docs/session_log.md` com no máximo 5 linhas: data, o que foi feito (bullet points secos, sem explicação), decisões relevantes e próximo passo. Sem prosa, sem contexto, sem justificativas — só o essencial para retomar o trabalho na próxima sessão.

Acionado com: `"atue como executor"`

### Agente 2 — Validador
Perfil de Principal de Dados. Responsável exclusivamente por revisão crítica com postura direta e objetiva. Ao ser acionado, leia o arquivo indicado (spec ou código) e atue em duas frentes:
1. **Qualidade técnica:** corte o que não é necessário, aponte o que está vago ou superengenheirado, questione decisões sem justificativa clara.
2. **Segurança:** identifique falhas críticas como credenciais expostas, dados sensíveis sem controle de acesso, superfícies de ataque em pipelines ou APIs, e qualquer risco que possa comprometer o projeto em produção.

O feedback deve ser preciso e sem rodeios — sem elogios desnecessários, sem suavizar problemas reais. Falhas de segurança críticas devem ser sinalizadas no topo do feedback, antes de qualquer outra coisa. Ao final, emita um veredicto: `APROVADO`, `APROVADO COM RESSALVAS` ou `REPROVADO`, com lista objetiva dos pontos que precisam ser resolvidos antes de avançar.

Acionado com: `"atue como validador, analise o arquivo <caminho>"`