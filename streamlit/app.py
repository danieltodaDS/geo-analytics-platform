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
    "transacoes_pix_per_capita",
]

DISPLAY_FEATURES = [
    "populacao_residente",
    "renda_media_per_capita",
    "pct_domicilios_com_internet",
    "penetracao_olist",
    "ticket_medio",
    "transacoes_pix_per_capita",
]

FEATURE_LABELS = {
    "populacao_residente": "População residente",
    "renda_media_per_capita": "Renda média per capita (R$)",
    "pct_domicilios_com_internet": "Domicílios c/ internet (%)",
    "penetracao_olist": "Penetração Olist (clientes/10k hab)",
    "ticket_medio": "Ticket médio (R$)",
    "transacoes_pix_per_capita": "Transações PIX per capita",
}

FEATURES_PCT = {"pct_domicilios_com_internet"}

RATIO_THRESHOLDS = (0.30, 0.70)

GITHUB_URL = "https://github.com/danieltodaDS/geo-analytics-platform"

CATEGORIAS_POPULACAO = [
    'Micro (< 10 mil)',
    'Pequeno (10–50 mil)',
    'Médio (50–200 mil)',
    'Grande (≥ 200 mil)',
]
CATEGORIAS_OLIST = [
    'Sem presença',
    'Baixa',
    'Média',
    'Alta',
]


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
    return client.query(sql).to_dataframe(create_bqstorage_client=False)


def build_matching_state(
    df: pd.DataFrame,
) -> tuple[pd.DataFrame, np.ndarray, np.ndarray]:
    df_match = df.dropna(subset=FEATURES).copy().reset_index(drop=True)
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

    outros = distancias[np.arange(len(distancias)) != pos]
    p10 = np.percentile(outros, 10)
    matches = result[result["id_municipio"] != municipio_id].nsmallest(k, "distancia")
    matches = matches.copy()
    matches["ratio"] = matches["distancia"] / p10
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
        rows=3,
        cols=2,
        subplot_titles=[FEATURE_LABELS[f] for f in DISPLAY_FEATURES],
    )

    for i, feat in enumerate(DISPLAY_FEATURES):
        row, col = divmod(i, 2)
        y_values = todos[feat].astype(float) * (100 if feat in FEATURES_PCT else 1)
        fig.add_trace(
            go.Bar(
                x=labels,
                y=y_values.tolist(),
                marker_color=cores,
                showlegend=False,
            ),
            row=row + 1,
            col=col + 1,
        )
        fig.update_yaxes(rangemode="tozero", row=row + 1, col=col + 1)

    fig.update_layout(
        height=900,
        margin=dict(t=60, b=20),
        xaxis_tickangle=-20,
        xaxis2_tickangle=-20,
        xaxis3_tickangle=-20,
        xaxis4_tickangle=-20,
        xaxis5_tickangle=-20,
        xaxis6_tickangle=-20,
    )
    return fig


def main() -> None:
    st.set_page_config(page_title="Geo Analytics — Municípios Similares", layout="wide")
    st.title("Municípios Similares")
    st.caption("Selecione um município para encontrar os 5 mais parecidos com base em perfil socioeconômico e de e-commerce.")

    df = load_data()

    # --- Sidebar: filtros ---
    st.sidebar.header("Filtros")

    sel_populacao = st.sidebar.multiselect(
        "Porte populacional",
        options=["Todos"] + CATEGORIAS_POPULACAO,
        default=["Todos"],
    )
    sel_olist = st.sidebar.multiselect(
        "Presença Olist",
        options=["Todos"] + CATEGORIAS_OLIST,
        default=["Todos"],
    )
    regioes = sorted(df["macroregiao_nome"].dropna().unique().tolist())
    sel_regiao = st.sidebar.multiselect(
        "Macrorregião",
        options=["Todos"] + regioes,
        default=["Todos"],
    )
    ufs = sorted(df["uf_sigla"].dropna().unique().tolist())
    sel_uf = st.sidebar.multiselect(
        "UF",
        options=["Todos"] + ufs,
        default=["Todos"],
    )

    # --- Aplicar filtros ---
    df_filtrado = df.copy()
    if "Todos" not in sel_populacao and sel_populacao:
        df_filtrado = df_filtrado[df_filtrado["categoria_populacao"].isin(sel_populacao)]
    if "Todos" not in sel_olist and sel_olist:
        df_filtrado = df_filtrado[df_filtrado["categoria_olist"].isin(sel_olist)]
    if "Todos" not in sel_regiao and sel_regiao:
        df_filtrado = df_filtrado[df_filtrado["macroregiao_nome"].isin(sel_regiao)]
    if "Todos" not in sel_uf and sel_uf:
        df_filtrado = df_filtrado[df_filtrado["uf_sigla"].isin(sel_uf)]

    st.sidebar.caption(f"{len(df_filtrado)} municípios no conjunto filtrado.")

    if len(df_filtrado) < 10:
        st.warning(
            f"{len(df_filtrado)} município(s) encontrado(s) — mínimo necessário é 10 para o cálculo de similaridade. "
            "Nota: apenas municípios com presença da Olist aparecem na lista."
        )
        return

    st.sidebar.divider()
    with st.sidebar.container(border=True):
        st.markdown(
            f"""
**ℹ️ Sobre este app**

Medir o impacto de uma funcionalidade, campanha ou iniciativa de produto exige mais do que comparar métricas antes e depois da mudança. Para avaliar incrementalidade, é necessário encontrar grupos de comparação que possuam características semelhantes ao grupo analisado.

Este app identifica municípios similares a um município selecionado utilizando indicadores socioeconômicos e de atividade econômica construídos a partir de dados públicos. O objetivo é demonstrar uma abordagem de matching para seleção de controles comparáveis, etapa fundamental em experimentação, avaliação de impacto e análises de causalidade.

Os dados são integrados por meio de um pipeline ELT completo em BigQuery, dbt e GCS e disponibilizados em uma aplicação interativa construída com Streamlit.

**Fontes:** Olist (2018) · IBGE Censo 2022 · BCB PIX (2020–2026)

[Repositório no GitHub →]({GITHUB_URL})
            """
        )

    # --- Matching usa df_filtrado ---
    df_match, X, VI = build_matching_state(df_filtrado)

    # --- Selectbox: apenas municípios do conjunto filtrado ---
    df_filtrado = df_filtrado.copy()
    df_filtrado["label"] = df_filtrado["nome_municipio"] + " - " + df_filtrado["uf_sigla"]
    opcoes = df_filtrado.sort_values("label")[["label", "id_municipio"]]
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
            "(`ticket_medio` sem dados)."
        )
        return

    alvo = df_match[df_match["id_municipio"] == municipio_id].iloc[0]
    matches = get_top_matches(municipio_id, df_match, X, VI)

    col_a, col_b, col_c, col_d = st.columns(4)
    col_a.metric(
        label="População residente",
        value=f"{int(alvo['populacao_residente']):,}".replace(",", "."),
        delta=alvo["categoria_populacao"],
        delta_color="off",
    )
    col_b.metric(
        label="Penetração Olist (cli./10k hab)",
        value=f"{alvo['penetracao_olist']:.2f}",
        delta=alvo["categoria_olist"],
        delta_color="off",
    )
    col_c.metric(
        label="Renda média per capita",
        value=f"R$ {alvo['renda_media_per_capita'] or 0:,.0f}".replace(",", "."),
    )
    col_d.metric(
        label="Domicílios c/ internet",
        value=f"{(alvo['pct_domicilios_com_internet'] or 0):.1%}",
    )

    st.subheader("Municípios mais similares")

    rows = []
    for i, (_, r) in enumerate(matches.iterrows(), 1):
        label_sim = classify(r["ratio"])
        rows.append({
            "#": i,
            "Município": r["nome_municipio"],
            "UF": r["uf_sigla"],
            "Similaridade": f"{label_sim} ({r['distancia']:.2f})",
        })

    st.dataframe(
        pd.DataFrame(rows).set_index("#"),
        width="stretch",
        hide_index=False,
    )

    st.subheader("Dados comparativos detalhados")
    st.caption("Para melhor visualização, acesse pelo desktop.")
    st.plotly_chart(plot_small_multiples(alvo, matches), width="stretch")


if __name__ == "__main__":
    main()
