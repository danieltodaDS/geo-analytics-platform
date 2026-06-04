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

_TABELAS = ["9606", "9605", "9514"]
_TIMEOUT = 60
_SLEEP_ENTRE_CHAMADAS = 0.5
_VOLUME_MINIMO = 11000


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
    url = f"https://apisidra.ibge.gov.br/values/t/{tabela}/n6/all/v/all/p/last"
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
    dest = (
        Path(base)
        / f"ibge_censo_{tabela}"
        / f"year={today.year}"
        / f"month={today.month:02d}"
        / f"day={today.day:02d}"
        / "data.parquet"
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(dest, index=False, compression="snappy")
    log.info("ibge_censo.parquet_gravado", tabela=tabela, destino_path=str(dest))


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
            if len(records) < _VOLUME_MINIMO:
                log.warning("ibge_censo.volume_baixo", tabela=tabela, total=len(records), minimo_esperado=_VOLUME_MINIMO)
            _gravar(records, tabela, today)
        except Exception:
            log.error("ibge_censo.erro_fatal", tabela=tabela, exc_info=True)
            raise  # write parcial é pior que sem write — aborta o run inteiro


if __name__ == "__main__":
    run()
