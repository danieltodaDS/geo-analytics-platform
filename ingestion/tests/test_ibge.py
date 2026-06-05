import os
from unittest.mock import MagicMock, patch

import pytest
import requests
import structlog.testing
from pydantic import ValidationError

import ingestion.src.ibge_censo as ibge_censo
import ingestion.src.ibge_localidades as ibge_localidades
from ingestion.src.ibge_censo import _parse_sidra
from ingestion.src.ibge_localidades import MunicipioRaw, _parse

# ─── Fixtures ────────────────────────────────────────────────────────────────

MUNICIPIO_COMPLETO = {
    "id": 5200050,
    "nome": "Abadia de Goiás",
    "regiao-imediata": {
        "id": 52008,
        "nome": "Goiânia",
        "regiao-intermediaria": {
            "id": 5203,
            "nome": "Goiânia",
            "UF": {
                "id": 52,
                "sigla": "GO",
                "nome": "Goiás",
                "regiao": {"id": 5, "sigla": "CO", "nome": "Centro-Oeste"},
            },
        },
    },
    "microrregiao": {
        "id": 52010,
        "nome": "Goiânia",
        "mesorregiao": {"id": 5203, "nome": "Centro Goiano"},
    },
}

SIDRA_HEADER = {
    "NC": "Nível Territorial (Código)",
    "NN": "Nível Territorial",
    "MC": "Unidade de Medida (Código)",
    "MN": "Unidade de Medida",
    "V": "Valor",
    "D1C": "Município (Código)",
    "D1N": "Município",
    "D2C": "Variável (Código)",
    "D2N": "Variável",
    "D3C": "Ano (Código)",
    "D3N": "Ano",
    "D4C": "Dimensão 4 (Código)",
    "D4N": "Dimensão 4",
}

SIDRA_RECORD = {
    "NC": "6",
    "NN": "Município",
    "MC": "Pessoa",
    "MN": "Pessoa",
    "V": "21494",
    "D1C": "1100015",
    "D1N": "Alta Floresta D'Oeste - RO",
    "D2C": "93",
    "D2N": "População residente",
    "D3C": "2022",
    "D3N": "2022",
    "D4C": "6561",
    "D4N": "Total",
}


# ─── ibge_localidades ────────────────────────────────────────────────────────

class TestMunicipioRaw:
    def test_parse_municipio_campos_obrigatorios(self):
        result = _parse(MUNICIPIO_COMPLETO)
        assert isinstance(result, MunicipioRaw)
        assert result.id_municipio == 5200050
        assert result.nome_municipio == "Abadia de Goiás"
        assert result.uf_sigla == "GO"
        assert result.macroregiao_sigla == "CO"
        assert result.mesorregiao_nome == "Centro Goiano"

    def test_parse_municipio_sem_regiao_imediata(self):
        record = {k: v for k, v in MUNICIPIO_COMPLETO.items() if k != "regiao-imediata"}
        with pytest.raises(ValidationError):
            _parse(record)

    def test_parse_municipio_id_tipo_correto(self):
        result = _parse(MUNICIPIO_COMPLETO)
        assert isinstance(result.id_municipio, int)

    def test_parse_municipio_sem_microrregiao(self):
        record = {**MUNICIPIO_COMPLETO, "microrregiao": None}
        result = _parse(record)
        assert result.microrregiao_id is None
        assert result.microrregiao_nome is None
        assert result.mesorregiao_id is None
        assert result.mesorregiao_nome is None


class TestVolumeGuardLocalidades:
    def test_volume_guard_warning(self, tmp_path):
        raw = [MUNICIPIO_COMPLETO] * 10
        with (
            patch.object(ibge_localidades, "_fetch", return_value=raw),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            ibge_localidades.run()
        assert any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )

    def test_volume_guard_ok(self, tmp_path):
        raw = [MUNICIPIO_COMPLETO] * 5500
        with (
            patch.object(ibge_localidades, "_fetch", return_value=raw),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            ibge_localidades.run()
        assert not any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )


# ─── ibge_censo ──────────────────────────────────────────────────────────────

class TestParseSidra:
    def test_parse_sidra_strip_header(self):
        data = [SIDRA_HEADER, SIDRA_RECORD, SIDRA_RECORD]
        result = _parse_sidra(data)
        assert len(result) == len(data) - 1

    def test_parse_sidra_valor_suprimido_traco(self):
        record = {**SIDRA_RECORD, "V": "-"}
        result = _parse_sidra([SIDRA_HEADER, record])
        assert result[0].V is None

    def test_parse_sidra_valor_suprimido_reticencias(self):
        record = {**SIDRA_RECORD, "V": "..."}
        result = _parse_sidra([SIDRA_HEADER, record])
        assert result[0].V is None

    def test_parse_sidra_valor_numerico(self):
        result = _parse_sidra([SIDRA_HEADER, SIDRA_RECORD])
        assert result[0].V == "21494"

    def test_parse_sidra_tabela_9605_sem_d5_d6(self):
        result = _parse_sidra([SIDRA_HEADER, SIDRA_RECORD])
        assert result[0].D5C is None
        assert result[0].D5N is None
        assert result[0].D6C is None
        assert result[0].D6N is None

    def test_parse_sidra_tabela_9606_com_d5_d6(self):
        record = {**SIDRA_RECORD, "D5C": "6794", "D5N": "Total", "D6C": "0", "D6N": "Total"}
        result = _parse_sidra([SIDRA_HEADER, record])
        assert result[0].D5C == "6794"
        assert result[0].D6C == "0"


class TestVolumeGuardCenso:
    def test_volume_guard_warning(self, tmp_path):
        data = [SIDRA_HEADER] + [SIDRA_RECORD] * 10
        with (
            patch.object(ibge_censo, "_fetch", return_value=data),
            patch.dict(os.environ, {"RAW_BASE_PATH": str(tmp_path)}),
            structlog.testing.capture_logs() as logs,
        ):
            ibge_censo.run()
        assert any(
            l["log_level"] == "warning" and "volume_baixo" in l["event"]
            for l in logs
        )


class TestRetry:
    def _mock_response(self, status_code: int) -> MagicMock:
        mock_resp = MagicMock()
        mock_resp.status_code = status_code
        mock_resp.raise_for_status.side_effect = requests.HTTPError(response=mock_resp)
        return mock_resp

    def test_retry_5xx(self):
        mock_resp = self._mock_response(500)
        with (
            patch("ingestion.src.ibge_censo.requests.get", return_value=mock_resp) as mock_get,
            patch("time.sleep"),
        ):
            with pytest.raises(requests.HTTPError):
                ibge_censo._fetch("9606")
        assert mock_get.call_count == 3

    def test_sem_retry_4xx(self):
        mock_resp = self._mock_response(404)
        with patch("ingestion.src.ibge_censo.requests.get", return_value=mock_resp) as mock_get:
            with pytest.raises(requests.HTTPError):
                ibge_censo._fetch("9606")
        assert mock_get.call_count == 1
