import os
from unittest.mock import MagicMock, patch

import pytest
import requests
import structlog.testing

import ingestion.src.bcb_pix as bcb_pix
from ingestion.src.bcb_pix import PixMunicipioRaw, _parse

# ─── Fixtures ────────────────────────────────────────────────────────────────

PIX_RECORD = {
    "AnoMes": 202202,
    "Municipio_Ibge": 4311759.0,
    "Municipio": "MANOEL VIANA",
    "Estado_Ibge": 43.0,
    "Estado": "RIO GRANDE DO SUL",
    "Sigla_Regiao": "SU",
    "Regiao": "SUL",
    "VL_PagadorPF": 5948465.27,
    "QT_PagadorPF": 17864,
    "VL_PagadorPJ": 1274988.24,
    "QT_PagadorPJ": 1636,
    "VL_RecebedorPF": 5728446.02,
    "QT_RecebedorPF": 12828,
    "VL_RecebedorPJ": 1966939.92,
    "QT_RecebedorPJ": 3744,
    "QT_PES_PagadorPF": 2054,
    "QT_PES_PagadorPJ": 151,
    "QT_PES_RecebedorPF": 1827,
    "QT_PES_RecebedorPJ": 153,
}

PIX_RECORD_NULO = {
    **PIX_RECORD,
    "Municipio_Ibge": None,
    "Estado_Ibge": None,
    "Sigla_Regiao": None,
}


# ─── PixMunicipioRaw ──────────────────────────────────────────────────────────

class TestPixMunicipioRaw:
    def test_parse_registro_completo(self):
        result = _parse(PIX_RECORD)
        assert isinstance(result, PixMunicipioRaw)
        assert result.AnoMes == 202202
        assert result.Municipio == "MANOEL VIANA"
        assert result.Sigla_Regiao == "SU"

    def test_parse_municipio_ibge_tipo_correto(self):
        result = _parse(PIX_RECORD)
        assert isinstance(result.Municipio_Ibge, int)
        assert isinstance(result.Estado_Ibge, int)

    def test_parse_descarta_registro_nulo(self):
        resultado = [_parse(r) for r in [PIX_RECORD_NULO, PIX_RECORD]]
        validos = [r for r in resultado if r is not None]
        assert len(validos) == 1
        assert validos[0].Municipio_Ibge == 4311759


# ─── Volume guard ─────────────────────────────────────────────────────────────

class TestVolumeGuardPix:
    def test_volume_guard_warning(self, tmp_path):
        raw = [PIX_RECORD] * 10
        with (
            patch.object(bcb_pix, "_fetch", return_value=raw),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            bcb_pix.run()
        assert any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )

    def test_volume_guard_ok(self, tmp_path):
        raw = [PIX_RECORD] * 10
        with (
            patch.object(bcb_pix, "_fetch", return_value=raw),
            patch.object(bcb_pix, "_VOLUME_MINIMO", 5),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            bcb_pix.run()
        assert not any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )


# ─── Retry ───────────────────────────────────────────────────────────────────

class TestRetry:
    def _mock_response(self, status_code: int) -> MagicMock:
        mock_resp = MagicMock()
        mock_resp.status_code = status_code
        mock_resp.raise_for_status.side_effect = requests.HTTPError(response=mock_resp)
        return mock_resp

    def test_retry_5xx(self):
        mock_resp = self._mock_response(500)
        with (
            patch("ingestion.src.bcb_pix.requests.get", return_value=mock_resp) as mock_get,
            patch("time.sleep"),
        ):
            with pytest.raises(requests.HTTPError):
                bcb_pix._fetch()
        assert mock_get.call_count == 3

    def test_sem_retry_4xx(self):
        mock_resp = self._mock_response(404)
        with patch("ingestion.src.bcb_pix.requests.get", return_value=mock_resp) as mock_get:
            with pytest.raises(requests.HTTPError):
                bcb_pix._fetch()
        assert mock_get.call_count == 1
