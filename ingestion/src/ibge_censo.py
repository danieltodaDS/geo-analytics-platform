import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
import structlog
from pydantic import BaseModel
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential

log = structlog.get_logger()

_TIMEOUT = 60
_SLEEP_ENTRE_CHAMADAS = 0.5

# c2072/77585 = existência de internet = Sim; c63/95826 = condição de ocupação = Total
_TABELAS_CONFIG: dict[str, dict] = {
    "9514":  {"url": "https://apisidra.ibge.gov.br/values/t/9514/n6/all/v/all/p/last",  "volume_minimo": 11000},
    "10295": {"url": "https://apisidra.ibge.gov.br/values/t/10295/n6/all/v/all/p/last", "volume_minimo": 11000},
    "9936":  {"url": "https://apisidra.ibge.gov.br/values/t/9936/n6/all/v/1000381/p/last/c2072/77585/c63/95826", "volume_minimo": 5000},
}
_TABELAS = list(_TABELAS_CONFIG)


class SidraRegistroRaw(BaseModel):
    NC: str
    NN: str
    MC: str
    MN: str
    V: Optional[str]
    D1C: str
    D1N: str
    D2C: str
    D2N: str
    D3C: str
    D3N: str
    D4C: str
    D4N: str
    D5C: Optional[str] = None
    D5N: Optional[str] = None
    D6C: Optional[str] = None
    D6N: Optional[str] = None


def _retryable(exc: BaseException) -> bool:
    if isinstance(exc, requests.HTTPError):
        return exc.response.status_code >= 500
    return isinstance(exc, (requests.ConnectionError, requests.Timeout))


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception(_retryable),
    reraise=True,
)
def _fetch(tabela: str) -> list[dict]:
    url = _TABELAS_CONFIG[tabela]["url"]
    r = requests.get(url, timeout=_TIMEOUT)
    r.raise_for_status()
    return r.json()


def _parse_sidra(data: list[dict]) -> list[SidraRegistroRaw]:
    # data[0] é o mapa de cabeçalho — ignorar
    records = []
    for row in data[1:]:
        v_raw = row.get("V")
        v = None if v_raw in ("-", "...") else v_raw
        records.append(SidraRegistroRaw(
            NC=row["NC"],
            NN=row["NN"],
            MC=row["MC"],
            MN=row["MN"],
            V=v,
            D1C=row["D1C"],
            D1N=row["D1N"],
            D2C=row["D2C"],
            D2N=row["D2N"],
            D3C=row["D3C"],
            D3N=row["D3N"],
            D4C=row["D4C"],
            D4N=row["D4N"],
            D5C=row.get("D5C"),
            D5N=row.get("D5N"),
            D6C=row.get("D6C"),
            D6N=row.get("D6N"),
        ))
    return records


def _gravar(records: list[SidraRegistroRaw], tabela: str, today: datetime) -> None:
    df = pd.DataFrame([r.model_dump() for r in records])
    base = os.environ.get("RAW_BASE_PATH", "data/raw")
    dest = f"{base}/ibge_censo_{tabela}/year={today.year}/month={today.month:02d}/day={today.day:02d}/data.parquet"
    if not dest.startswith("gs://"):
        Path(dest).parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(dest, index=False, compression="snappy")
    log.info("ibge_censo.parquet_gravado", tabela=tabela, destino_path=dest)


def run() -> None:
    today = datetime.now(tz=timezone.utc)
    for i, tabela in enumerate(_TABELAS):
        if i > 0:
            time.sleep(_SLEEP_ENTRE_CHAMADAS)
        log.info("ibge_censo.inicio", tabela=tabela)
        try:
            data = _fetch(tabela)
            records = _parse_sidra(data)
            log.info("ibge_censo.fetch_ok", tabela=tabela, total_registros=len(records))
            minimo = _TABELAS_CONFIG[tabela]["volume_minimo"]
            if len(records) < minimo:
                log.warning("ibge_censo.volume_baixo", tabela=tabela, total=len(records), minimo_esperado=minimo)
            _gravar(records, tabela, today)
        except Exception:
            log.error("ibge_censo.erro_fatal", tabela=tabela, exc_info=True)
            raise  # write parcial é pior que sem write — aborta o run inteiro


if __name__ == "__main__":
    run()
