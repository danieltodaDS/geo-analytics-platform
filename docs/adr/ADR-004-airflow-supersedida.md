# ADR-004: Airflow Local como Orquestrador de Desenvolvimento

**Status:** Supersedida pela ADR-006
**Data original:** Início do projeto
**Data de supersedência:** Junho/2026

---

## Decisão original

Usar Apache Airflow via Docker Compose para orquestração local. Cloud Scheduler + Cloud Run em produção.

## Por que foi supersedida

Durante a fase de exploração das fontes de negócio, todos os datasets confirmaram-se **históricos estáticos** (Olist: período 2015–2018, carga batch única). Sem dados incrementais reais, o valor central do Airflow desaparece:

- `execution_date` não tem semântica útil para dados que não atualizam
- `catchup` de execuções passadas não faz sentido para uma carga única
- Janelas temporais (`data_interval_start/end`) não se aplicam

O que restaria seria um cron job com dependências — entregável pelo Makefile sem a complexidade do Airflow.

Usar Airflow neste contexto seria overengineering documentado: adiciona Docker Compose, workers, scheduler, webserver e banco de metadados para resolver um problema que não existe.

## Consequências da supersedência

- Diretório `airflow/` removido do repositório
- Feature de "Ingestão com Airflow" removida do roadmap
- A ausência do Airflow é uma **decisão documentada** nesta ADR — não uma lacuna ou dívida técnica
- Ver ADR-006 para a solução que substituiu

## Lição registrada

Explorar os dados antes de especificar a infraestrutura evitou implementar uma camada inteira de orquestração desnecessária. O ciclo Explorar → Entender → Especificar → Produtizar protegeu o projeto deste overengineering.
