import os

import numpy as np
from google.oauth2 import service_account
import pandas as pd
import streamlit as st
from google.cloud import bigquery
from plotly.subplots import make_subplots
import plotly.graph_objects as go
from scipy.spatial.distance import cdist

FEATURES = [
    "populacao_residente",
    "renda_media_per_capita",
    "pct_domicilios_com_internet",
    "penetracao_olist",
    "ticket_medio",
    "pct_pagamento_cartao",
]

DISPLAY_FEATURES = [
    "populacao_residente",
    "renda_media_per_capita",
    "pct_domicilios_com_internet",
    "penetracao_olist",
]

FEATURE_LABELS = {
    "populacao_residente": "População residente",
    "renda_media_per_capita": "Renda média per capita (R$)",
    "pct_domicilios_com_internet": "Domicílios c/ internet (%)",
    "penetracao_olist": "Penetração Olist (pedidos/hab)",
}

RATIO_THRESHOLDS = (0.30, 0.70)


@st.cache_data(ttl=3600)
def load_data() -> pd.DataFrame:
    try:
        has_sa = "gcp_service_account" in st.secrets
    except Exception:
        has_sa = False

    if has_sa:
        # Streamlit Community Cloud: credenciais via st.secrets
        credentials = service_account.Credentials.from_service_account_info(
            st.secrets["gcp_service_account"],
            scopes=["https://www.googleapis.com/auth/bigquery"],
        )
        project = st.secrets["gcp_service_account"]["project_id"]
        dataset = st.secrets.get("gcp_dataset_marts", "marts")
        client = bigquery.Client(project=project, credentials=credentials)
    else:
        # Local: ADC via gcloud auth application-default login
        project = os.environ["GCP_PROJECT"]
        dataset = os.environ["GCP_DATASET_MARTS"]
        client = bigquery.Client(project=project)
    sql = f"SELECT * FROM `{project}.{dataset}.mart_geo_analytics`"
    return client.query(sql).to_dataframe()


@st.cache_data
def build_matching_state(
    _df: pd.DataFrame,
) -> tuple[pd.DataFrame, np.ndarray, np.ndarray]:
    df_match = _df.dropna(subset=FEATURES).copy().reset_index(drop=True)
    X = df_match[FEATURES].values
    VI = np.linalg.inv(np.cov(X.T))
    return df_match, X, VI


def get_top_matches(
    municipio_id: int,
    df_match: pd.DataFrame,
    X: np.ndarray,
    VI: np.ndarray,
    k: int = 5,
) -> pd.DataFrame:
    pos = df_match.index[df_match["id_municipio"] == municipio_id][0]
    x_trat = X[pos].reshape(1, -1)
    distancias = cdist(x_trat, X, metric="mahalanobis", VI=VI).flatten()

    result = df_match.copy()
    result["distancia"] = distancias

    mediana = np.median(distancias[np.arange(len(distancias)) != pos])
    matches = result[result["id_municipio"] != municipio_id].nsmallest(k, "distancia")
    matches = matches.copy()
    matches["ratio"] = matches["distancia"] / mediana
    return matches


def classify(ratio: float) -> str:
    low, high = RATIO_THRESHOLDS
    if ratio < low:
        return "🟢 Muito parecido"
    if ratio < high:
        return "🟡 Razoavelmente parecido"
    return "🔴 Pouco parecido"


def plot_small_multiples(alvo: pd.Series, matches: pd.DataFrame) -> go.Figure:
    todos = pd.concat([alvo.to_frame().T, matches], ignore_index=True)
    labels = (
        [f"{alvo['nome_municipio']} ({alvo['uf_sigla']}) ★"]
        + [f"{r['nome_municipio']} ({r['uf_sigla']})" for _, r in matches.iterrows()]
    )
    cores = ["#1f77b4"] + ["#aec7e8"] * len(matches)

    fig = make_subplots(
        rows=2,
        cols=2,
        subplot_titles=[FEATURE_LABELS[f] for f in DISPLAY_FEATURES],
    )

    for i, feat in enumerate(DISPLAY_FEATURES):
        row, col = divmod(i, 2)
        fig.add_trace(
            go.Bar(
                x=labels,
                y=todos[feat].astype(float).tolist(),
                marker_color=cores,
                showlegend=False,
            ),
            row=row + 1,
            col=col + 1,
        )
        fig.update_yaxes(rangemode="tozero", row=row + 1, col=col + 1)

    fig.update_layout(
        height=520,
        margin=dict(t=60, b=20),
        xaxis_tickangle=-20,
        xaxis2_tickangle=-20,
        xaxis3_tickangle=-20,
        xaxis4_tickangle=-20,
    )
    return fig


def main() -> None:
    st.set_page_config(page_title="Geo Analytics — Matching", layout="wide")
    st.title("Matching por Mahalanobis")
    st.caption("Selecione um município para encontrar os 5 mais similares com base em perfil socioeconômico e de e-commerce.")

    df = load_data()
    df_match, X, VI = build_matching_state(df)

    df_todos = df.copy()
    df_todos["label"] = df_todos["nome_municipio"] + " - " + df_todos["uf_sigla"]
    opcoes = df_todos.sort_values("label")[["label", "id_municipio"]]
    label_para_id = dict(zip(opcoes["label"], opcoes["id_municipio"]))

    label_selecionado = st.selectbox(
        "Selecione o município:",
        options=[""] + opcoes["label"].tolist(),
        index=0,
    )

    if not label_selecionado:
        st.info("Selecione um município para ver os pares.")
        return

    municipio_id = label_para_id[label_selecionado]

    if municipio_id not in df_match["id_municipio"].values:
        st.warning(
            "Este município não está disponível para matching por ausência de covariáveis completas "
            f"(`pct_pagamento_cartao` ou `ticket_medio` sem dados)."
        )
        return

    alvo = df_match[df_match["id_municipio"] == municipio_id].iloc[0]
    matches = get_top_matches(municipio_id, df_match, X, VI)

    st.subheader("Municípios mais similares")

    rows = []
    for i, (_, r) in enumerate(matches.iterrows(), 1):
        label_sim = classify(r["ratio"])
        rows.append({
            "#": i,
            "Município": r["nome_municipio"],
            "UF": r["uf_sigla"],
            "Similaridade": label_sim,
        })

    st.dataframe(
        pd.DataFrame(rows).set_index("#"),
        width="stretch",
        hide_index=False,
    )

    st.subheader("Comparativo de covariáveis")
    st.plotly_chart(plot_small_multiples(alvo, matches), width="stretch")


if __name__ == "__main__":
    main()
