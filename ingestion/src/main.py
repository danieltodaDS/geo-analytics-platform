import os
from datetime import datetime, timezone

import functions_framework
import structlog
from cloudevents.http import CloudEvent

from olist import _TABELAS, _process_table

log = structlog.get_logger()

# filename → (tabela_key, model_class)
_CSV_TO_TABELA = {csv: (key, model) for key, (csv, model) in _TABELAS.items()}


@functions_framework.cloud_event
def handle_event(cloud_event: CloudEvent) -> None:
    data = cloud_event.data
    bucket = data["bucket"]
    name = data["name"]

    filename = name.split("/")[-1]
    match = _CSV_TO_TABELA.get(filename)

    if match is None:
        log.info("olist_function.arquivo_nao_reconhecido", filename=filename, path=name)
        return

    tabela, model = match
    prefix = "/".join(name.split("/")[:-1])
    olist_base = f"gs://{bucket}/{prefix}"
    raw_base = os.environ["RAW_BASE_PATH"]
    today = datetime.now(tz=timezone.utc)

    log.info("olist_function.inicio", tabela=tabela, source_path=f"{olist_base}/{filename}")
    _process_table(tabela, filename, model, olist_base, raw_base, today)
    log.info("olist_function.concluido", tabela=tabela)
