import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
import structlog
from pydantic import BaseModel
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential

log = structlog.get_logger()

_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/municipios"
_VOLUME_MINIMO = 5500


class MunicipioRaw(BaseModel):
    id_municipio: int
    nome_municipio: str
    regiao_imediata_id: int
    regiao_imediata_nome: str
    regiao_interm_id: int
    regiao_interm_nome: str
    uf_id: int
    uf_sigla: str
    uf_nome: str
    macroregiao_id: int
    macroregiao_sigla: str
    macroregiao_nome: str
    microrregiao_id: int
    microrregiao_nome: str
    mesorregiao_id: int
    mesorregiao_nome: str


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
    r = requests.get(_URL, timeout=30)
    r.raise_for_status()
    return r.json()


def _parse(record: dict) -> MunicipioRaw:
    ri = record.get("regiao-imediata") or {}
    rinterm = ri.get("regiao-intermediaria") or {}
    uf = rinterm.get("UF") or {}
    macro = uf.get("regiao") or {}
    micro = record.get("microrregiao") or {}
    meso = micro.get("mesorregiao") or {}
    return MunicipioRaw(
        id_municipio=record.get("id"),
        nome_municipio=record.get("nome"),
        regiao_imediata_id=ri.get("id"),
        regiao_imediata_nome=ri.get("nome"),
        regiao_interm_id=rinterm.get("id"),
        regiao_interm_nome=rinterm.get("nome"),
        uf_id=uf.get("id"),
        uf_sigla=uf.get("sigla"),
        uf_nome=uf.get("nome"),
        macroregiao_id=macro.get("id"),
        macroregiao_sigla=macro.get("sigla"),
        macroregiao_nome=macro.get("nome"),
        microrregiao_id=micro.get("id"),
        microrregiao_nome=micro.get("nome"),
        mesorregiao_id=meso.get("id"),
        mesorregiao_nome=meso.get("nome"),
    )


def run() -> None:
    log.info("ibge_localidades.inicio")
    try:
        raw = _fetch()
        log.info("ibge_localidades.fetch_ok", total_municipios=len(raw))

        if len(raw) < _VOLUME_MINIMO:
            log.warning("ibge_localidades.volume_baixo", total=len(raw), minimo_esperado=_VOLUME_MINIMO)

        records = [_parse(m).model_dump() for m in raw]
        df = pd.DataFrame(records)

        today = datetime.now(tz=timezone.utc)
        base = os.environ.get("RAW_BASE_PATH", "data/raw")
        dest = (
            Path(base)
            / "ibge_localidades"
            / f"year={today.year}"
            / f"month={today.month:02d}"
            / f"day={today.day:02d}"
            / "data.parquet"
        )
        dest.parent.mkdir(parents=True, exist_ok=True)
        df.to_parquet(dest, index=False, compression="snappy")
        log.info("ibge_localidades.parquet_gravado", destino_path=str(dest))
    except Exception:
        log.error("ibge_localidades.erro_fatal", exc_info=True)
        raise


if __name__ == "__main__":
    run()
