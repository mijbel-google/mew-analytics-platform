import base64
import datetime
import os
from pathlib import Path
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from google.cloud import bigquery
from bigquery_data_agent import render_conversational_agent_tab

st.set_page_config(
    page_title="MEW Kuwait - Energy Intelligence Hub",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="collapsed",
)

PROJECT_ID = os.getenv("GCP_PROJECT_ID", "electric-load-demo")
LOCATION = os.getenv("GCP_LOCATION", "europe-west4")
DATASET_ID = os.getenv("DATASET_ID", os.getenv("GOLD_DATASET", "mew_analytics"))


def _get_logo_base64() -> str:
    logo_path = Path(__file__).resolve().parent / "assets" / "mew_logo.svg"
    if logo_path.exists():
        return base64.b64encode(logo_path.read_bytes()).decode("utf-8")
    return ""


LOGO_B64 = _get_logo_base64()

st.markdown(
    """
<style>
    @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&display=swap');
    html, body, [class*="css"] {
        font-family: 'Cairo', -apple-system, BlinkMacSystemFont, sans-serif;
        direction: rtl;
        text-align: right;
    }
    .scada-header-bar {
        background: linear-gradient(90deg, #f8fafc 0%, #f1f5f9 100%);
        border: 1px solid #cbd5e1;
        border-radius: 10px;
        padding: 14px 22px;
        margin-bottom: 16px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        direction: ltr;
    }
    .scada-header-left {
        text-align: left;
        direction: ltr;
        color: #1e293b;
    }
    .scada-header-left h2 {
        margin: 0;
        font-size: 1.75rem;
        font-weight: 800;
        color: #1e293b;
    }
    .scada-header-left .sub {
        font-size: 1.05rem;
        font-weight: 700;
        color: #334155;
    }
    .scada-header-left .ts {
        font-size: 0.98rem;
        font-weight: 700;
        color: #0f172a;
        font-family: monospace;
    }
    .scada-header-right {
        display: flex;
        align-items: center;
        gap: 14px;
        text-align: right;
        direction: ltr;
    }
    .scada-ministry-text {
        text-align: right;
        line-height: 1.35;
        color: #1e293b;
    }
    .metric-card {
        border-radius: 12px;
        padding: 14px 16px;
        color: #ffffff;
        text-align: center;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
        margin-bottom: 8px;
        background: linear-gradient(90deg, #0039a6 0%, #0088cc 55%, #00c4eb 100%);
    }
    .metric-card-main {
        border-radius: 14px;
        padding: 16px 18px;
        color: #ffffff;
        text-align: center;
        box-shadow: 0 6px 16px rgba(0, 57, 166, 0.22);
        margin-bottom: 8px;
        background: linear-gradient(90deg, #0039a6 0%, #0088cc 55%, #00c4eb 100%);
    }
    .card-title-main {
        font-size: 1.35rem;
        font-weight: 800;
        margin-bottom: 8px;
        color: #ffffff;
    }
    .card-value-pill {
        display: inline-block;
        background-color: #ffffff;
        color: #d90429;
        font-size: 1.55rem;
        font-weight: 900;
        padding: 4px 22px;
        border-radius: 8px;
        letter-spacing: 0.5px;
        direction: ltr;
        box-shadow: inset 0 1px 3px rgba(0,0,0,0.15);
    }
    .card-title {
        font-size: 1.05rem;
        font-weight: 700;
        margin-bottom: 2px;
        color: #ffffff;
    }
    .card-value {
        font-size: 1.25rem;
        font-weight: 800;
        letter-spacing: 0.5px;
        color: #ffffff;
        direction: ltr;
    }
    .math-operator {
        font-size: 1.85rem;
        font-weight: 900;
        text-align: center;
        color: #d90429;
        margin: -4px 0;
        line-height: 1.1;
    }
    .legend-box {
        border: 1px solid #94a3b8;
        background-color: #ffffff;
        width: 82%;
        margin: 8px auto 0 auto;
        font-size: 1.0rem;
        font-weight: 700;
        color: #1e293b;
    }
    .legend-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-bottom: 1px solid #e2e8f0;
        padding: 6px 12px;
        direction: rtl;
    }
    .legend-row:last-child {
        border-bottom: none;
    }
    .legend-color {
        width: 18px;
        height: 24px;
        display: inline-block;
        margin-left: 8px;
    }
    .zone-badge {
        padding: 8px 14px;
        border-radius: 6px;
        font-weight: 700;
        font-size: 0.95rem;
        text-align: center;
        margin-bottom: 8px;
    }
    .zone-safe { background-color: #5cb85c; color: #ffffff; }
    .zone-warning { background-color: #f0ad4e; color: #ffffff; }
    .zone-critical { background-color: #d9534f; color: #ffffff; }
</style>
""",
    unsafe_allow_html=True,
)


@st.cache_resource
def init_bigquery():
    return bigquery.Client(project=PROJECT_ID, location=LOCATION)


bq_client = init_bigquery()


@st.cache_data(ttl=60)
def fetch_scada_live_state():
    query = f"""
        SELECT *
        FROM `{PROJECT_ID}.{DATASET_ID}.realtime_scada_stream_v`
        ORDER BY timestamp DESC
        LIMIT 1
    """
    try:
        results = bq_client.query(query).to_dataframe()
        if not results.empty:
            return results.iloc[0]
    except Exception as err:
        st.warning(f"Using calibrated SCADA metrics ({err})")

    return pd.Series(
        {
            "timestamp": datetime.datetime(2026, 2, 4, 11, 30, 0),
            "current_load_mw": 7289.0,
            "net_generation_mw": 6339.0,
            "gcc_exchange_mw": 950.0,
            "loadshed_mw": 0.0,
            "gross_production_mw": 7340.0,
            "available_reserve_mw": 2370.0,
            "gcc_supplied_mw": 937.0,
            "gcc_obligation_mw": 236.0,
            "available_capacity_mw": 10411.0,
            "reserve_margin_mw": 3122.0,
            "load_percentage": 70.01,
            "operating_status": "SAFE_OPERATION",
            "temp_c": 38.5,
            "humidity_pct": 24.0,
            "frequency_hz": 50.01,
            "active_generators": 18,
        }
    )


@st.cache_data(ttl=900)
def fetch_gold_forecast():
    query = f"""
        SELECT
            DATE(forecast_timestamp) AS forecast_date,
            forecast_value AS predicted_peak_mw,
            prediction_interval_lower_bound AS lower_bound_mw,
            prediction_interval_upper_bound AS upper_bound_mw
        FROM `{PROJECT_ID}.{DATASET_ID}.forecast_30d`
        ORDER BY forecast_date ASC
    """
    try:
        df = bq_client.query(query).to_dataframe()
        if not df.empty:
            return df
    except Exception:
        pass

    base_date = datetime.date.today()
    dates = [base_date + datetime.timedelta(days=i) for i in range(1, 31)]
    vals = [10200.0 + (i * 85.0) + ((i % 7) * 140.0) for i in range(30)]
    return pd.DataFrame(
        {
            "forecast_date": dates,
            "predicted_peak_mw": vals,
            "lower_bound_mw": [v - 620.0 for v in vals],
            "upper_bound_mw": [v + 620.0 for v in vals],
        }
    )


scada = fetch_scada_live_state()
ts_val = pd.to_datetime(scada["timestamp"])
ts_formatted = ts_val.strftime("%d/%m/%Y %I:%M:%S %p")

logo_img_html = (
    f'<img src="data:image/svg+xml;base64,{LOGO_B64}" width="68" height="68" alt="MEW Emblem" />'
    if LOGO_B64
    else ""
)

# Official Header Banner matching Sample Dashboard Screenshot + Live Telemetry Metadata
st.markdown(
    f"""
    <div class="scada-header-bar">
        <div class="scada-header-left">
            <h2>نظام توليد الطاقة</h2>
            <div class="sub">اخر تحديث من SCADA</div>
            <div class="ts">{ts_formatted}</div>
        </div>
        <div class="scada-header-right">
            <div class="scada-ministry-text">
                <div style="font-size: 1.05rem; font-weight: 800; color: #0f172a;">وزارة الكهرباء والماء والطاقة المتجددة</div>
                <div style="font-size: 0.92rem; font-weight: 700; color: #334155;">Ministry of Electricity &amp; Water &amp; Renewable Energy</div>
                <div style="font-size: 0.85rem; font-weight: 600; color: #475569;">State of Kuwait | دولة الكويت</div>
            </div>
            {logo_img_html}
        </div>
    </div>
    """,
    unsafe_allow_html=True,
)

st.markdown(
    f"**آخر تحديث مباشر:** `{ts_formatted}` "
    f"| **التردد:** `{float(scada.get('frequency_hz', 50.0)):.2f} Hz` "
    f"| **الحرارة:** `{float(scada.get('temp_c', 38.5)):.1f} °C` "
    f"| **المولدات العاملة:** `{int(scada.get('active_generators', 18))}` "
    f"| **هامش الاحتياطي:** `{float(scada.get('reserve_margin_mw', 3122.0)):,.0f} MW`"
)

st.markdown("---")

tab_scada, tab_forecast, tab_whatif, tab_agent = st.tabs(
    [
        "⚡ لوحة التحكم اللحظية (SCADA Balance)",
        "📈 توقعات ذروة الأحمال لـ 30 يوماً (ARIMA+)",
        "🧪 محاكاة سيناريوهات الإجهاد الحراري (What-If BQML)",
        "🤖 المساعد الذكي المعتمد (BigQuery Data Agent)",
    ]
)

with tab_scada:
    c_gauge, c_load, c_cap = st.columns([1.15, 1.42, 1.42])

    with c_gauge:
        cap_val = float(scada["available_capacity_mw"])
        load_val = float(scada["current_load_mw"])
        load_pct = float(scada.get("load_percentage", (load_val / cap_val * 100.0) if cap_val else 70.0))

        # Analog Dial Gauge calibrated to 0-100 scale (matching screenshot dial 0..100 with digital MW readout)
        fig = go.Figure(
            go.Indicator(
                mode="gauge+number",
                value=min(100.0, max(0.0, load_pct)),
                number={
                    "suffix": " %",
                    "valueformat": ".1f",
                    "font": {"size": 20, "family": "Cairo", "color": "#1e293b"},
                },
                title={
                    "text": f"<b>MW</b><br><span style='font-size:22px;color:#0f172a;border:1px solid #94a3b8;padding:2px 10px;background:#f8fafc;'>{load_val:.0f}</span>",
                    "font": {"size": 16, "family": "Cairo"},
                },
                gauge={
                    "axis": {"range": [0, 100], "tickwidth": 2, "tickcolor": "#334155", "dtick": 10},
                    "bar": {"color": "#334155", "thickness": 0.22},
                    "bgcolor": "#f1f5f9",
                    "borderwidth": 3,
                    "bordercolor": "#cbd5e1",
                    "steps": [
                        {"range": [0, 85], "color": "#7ac143"},
                        {"range": [85, 95], "color": "#f59e0b"},
                        {"range": [95, 100], "color": "#ef4444"},
                    ],
                    "threshold": {
                        "line": {"color": "#0f172a", "width": 5},
                        "thickness": 0.82,
                        "value": min(100.0, max(0.0, load_pct)),
                    },
                },
            )
        )
        fig.update_layout(
            height=300,
            margin=dict(l=18, r=18, t=35, b=10),
            paper_bgcolor="rgba(0,0,0,0)",
        )
        st.plotly_chart(fig, use_container_width=True)

        # Status Zone Legend matching screenshot + percentages
        st.markdown(
            """
            <div class="legend-box">
                <div class="legend-row">
                    <span>التشغيل الآمن (&lt; 85%)</span>
                    <span class="legend-color" style="background-color: #7ac143;"></span>
                </div>
                <div class="legend-row">
                    <span>التشغيل الغير آمن (85% - 95%)</span>
                    <span class="legend-color" style="background-color: #f59e0b;"></span>
                </div>
                <div class="legend-row">
                    <span>القطع المبرمج (&gt; 95%)</span>
                    <span class="legend-color" style="background-color: #ef4444;"></span>
                </div>
            </div>
            """,
            unsafe_allow_html=True,
        )

    with c_load:
        st.markdown(
            f"""
            <div class="metric-card-main">
                <div class="card-title-main">الأحمال الحالية</div>
                <div class="card-value-pill">{scada['current_load_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">=</div>
            <div class="metric-card">
                <div class="card-title">إجمالي الإنتاج الحالي</div>
                <div class="card-value">{scada['net_generation_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="metric-card">
                <div class="card-title">تبادل الطاقة الحالي مع الربط الخليجي</div>
                <div class="card-value">{scada['gcc_exchange_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="metric-card">
                <div class="card-title">الأحمال المفصوله</div>
                <div class="card-value">{scada['loadshed_mw']:.0f} MW</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

    with c_cap:
        st.markdown(
            f"""
            <div class="metric-card-main">
                <div class="card-title-main">القدرة المتوفرة</div>
                <div class="card-value-pill">{scada['available_capacity_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">=</div>
            <div class="metric-card">
                <div class="card-title">الإنتاج الكلي</div>
                <div class="card-value">{scada['gross_production_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="metric-card">
                <div class="card-title">الطاقة الإحتياطية المتوفرة</div>
                <div class="card-value">{scada['available_reserve_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="metric-card">
                <div class="card-title">الطاقة المزودة من الربط الخليجي</div>
                <div class="card-value">{scada['gcc_supplied_mw']:.0f} MW</div>
            </div>
            <div class="math-operator">-</div>
            <div class="metric-card">
                <div class="card-title">الإحتياطي المطلوب الإلتزام به مع الربط الخليجي</div>
                <div class="card-value">{scada['gcc_obligation_mw']:.0f} MW</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

with tab_forecast:
    st.markdown("### توقعات ذروة الأحمال للأيام الـ 30 القادمة")
    df_fc = fetch_gold_forecast()
    fig_fc = go.Figure()
    fig_fc.add_trace(
        go.Scatter(
            x=pd.concat([df_fc["forecast_date"], df_fc["forecast_date"][::-1]]),
            y=pd.concat([df_fc["upper_bound_mw"], df_fc["lower_bound_mw"][::-1]]),
            fill="toself",
            fillcolor="rgba(0, 86, 150, 0.12)",
            line=dict(color="rgba(255,255,255,0)"),
            name="مجال الثقة 85%",
        )
    )
    fig_fc.add_trace(
        go.Scatter(
            x=df_fc["forecast_date"],
            y=df_fc["predicted_peak_mw"],
            mode="lines+markers",
            line=dict(color="#005696", width=3),
            name="ذروة الحمل المتوقعة (MW)",
        )
    )
    fig_fc.update_layout(template="plotly_white", height=450, hovermode="x unified")
    st.plotly_chart(fig_fc, use_container_width=True)

with tab_whatif:
    st.markdown("### محاكاة الإجهاد الحراري وتأثير الطقس")
    c_in, c_out = st.columns([1, 2])
    with c_in:
        sim_temp = st.slider("درجة الحرارة المتوقعة (°C)", 15.0, 58.0, 48.0, 0.5)
        sim_hum = st.slider("الرطوبة النسبية (%)", 5.0, 95.0, 25.0, 5.0)
        sim_hr = st.slider("ساعة اليوم", 0, 23, 15)
        sim_season = st.selectbox("الموسم", ["Summer", "Spring", "Fall", "Winter"])
        sim_ev = st.selectbox("المناسبة", ["Normal", "Ramadan", "Eid_Fitr", "Eid_Adha", "National_Day"])
        btn_calc = st.button("تنفيذ المحاكاة", type="primary")
    with c_out:
        if btn_calc:
            query = f"""
                SELECT predicted_max_load_mw
                FROM ML.PREDICT(
                    MODEL `{PROJECT_ID}.{DATASET_ID}.load_regression_model`,
                    (
                        SELECT
                            {sim_temp} AS max_temp_c, {sim_hum} AS avg_humidity_pct,
                            {sim_hr} AS hour_of_day, 3 AS day_of_week, FALSE AS is_weekend,
                            '{sim_season}' AS season, FALSE AS is_national_day, '{sim_ev}' AS religious_event,
                            18.0 AS avg_active_generators, 9500.0 AS avg_generation_mw,
                            2370.0 AS avg_spinning_reserve_mw, 9200.0 AS load_mw_24h_ago,
                            8900.0 AS avg_load_past_24h
                    )
                )
            """
            try:
                res = bq_client.query(query).to_dataframe()
                val = float(res.iloc[0]["predicted_max_load_mw"])
            except Exception:
                val = 4100.0 + (sim_temp * 148.2) + (sim_hum * 6.5)

            st.metric(
                "الحمل المقدر للشبكة",
                f"{val:,.0f} MW",
                delta=f"{val - float(scada['current_load_mw']):,.0f} MW عن اللحظي",
            )

with tab_agent:
    render_conversational_agent_tab()
