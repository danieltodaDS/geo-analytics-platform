import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
import structlog
from pydantic import BaseModel, field_validator
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential

log = structlog.get_logger()

_URL = (
    "https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata"
    "/TransacoesPixPorMunicipio(DataBase='202011')"
)
_VOLUME_MINIMO = 378_000


class PixMunicipioRaw(BaseModel):
    AnoMes: int
    Municipio_Ibge: int
    Municipio: str
    Estado_Ibge: int
    Estado: str
    Sigla_Regiao: str
    Regiao: str
    VL_PagadorPF: float
    QT_PagadorPF: int
    VL_PagadorPJ: float
    QT_PagadorPJ: int
    VL_RecebedorPF: float
    QT_RecebedorPF: int
    VL_RecebedorPJ: float
    QT_RecebedorPJ: int
    QT_PES_PagadorPF: int
    QT_PES_PagadorPJ: int
    QT_PES_RecebedorPF: int
    QT_PES_RecebedorPJ: int

    @field_validator("Municipio_Ibge", "Estado_Ibge", mode="before")
    @classmethod
    def cast_float_to_int(cls, v):
        # Pré-condição: v não é None — registros nulos são filtrados antes de chegar aqui
        return int(v)


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
def _fetch() -> list[dict]:
    r = requests.get(_URL, params={"$format": "json"}, timeout=120)
    r.raise_for_status()
    return r.json()["value"]


def _parse(record: dict) -> PixMunicipioRaw | None:
    if record.get("Municipio_Ibge") is None or record.get("Estado_Ibge") is None:
        return None
    return PixMunicipioRaw(**record)


def run() -> None:
    log.info("bcb_pix.inicio")
    try:
        raw = _fetch()
        log.info("bcb_pix.fetch_ok", total_registros=len(raw))

        parsed = [_parse(r) for r in raw]
        descartados = sum(1 for r in parsed if r is None)
        log.info("bcb_pix.nulos_descartados", total_descartados=descartados)

        records = [r.model_dump() for r in parsed if r is not None]

        if len(records) < _VOLUME_MINIMO:
            log.warning("bcb_pix.volume_baixo", total=len(records), minimo_esperado=_VOLUME_MINIMO)

        df = pd.DataFrame(records)

        today = datetime.now(tz=timezone.utc)
        base = os.environ.get("RAW_BASE_PATH", "data/raw")
        dest = (
            Path(base)
            / "bcb_pix"
            / f"year={today.year}"
            / f"month={today.month:02d}"
            / f"day={today.day:02d}"
            / "data.parquet"
        )
        dest.parent.mkdir(parents=True, exist_ok=True)
        df.to_parquet(dest, index=False, compression="snappy")
        log.info("bcb_pix.parquet_gravado", destino_path=str(dest))
    except Exception:
        log.error("bcb_pix.erro_fatal", exc_info=True)
        raise


if __name__ == "__main__":
    run()
