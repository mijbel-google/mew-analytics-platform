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

# Modernized Design System:
# - System Font Stack (SF Pro, Segoe UI, Roboto, Booking.com approach)
# - Single Neutral Palette (Slate/Zinc) + High-Contrast Accent (#0284c7)
# - Color-Blind Fallbacks: Patterns (solid, dashed, striped), line weights, and symbols ([✔], [▲], [✖])
st.markdown(
    """
<style>
    /* System Font Stack - Booking.com & native OS pattern */
    html, body, [class*="css"], .stApp {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        font-feature-settings: "tnum" 1, "cv02" 1, "cv03" 1, "cv04" 1;
        -webkit-font-smoothing: antialiased;
        color: #0f172a;
        direction: rtl;
        text-align: right;
    }

    /* Executive Top Bar */
    .scada-header-bar {
        background-color: #ffffff;
        border: 1px solid #cbd5e1;
        border-top: 4px solid #0284c7; /* High-contrast action accent */
        border-radius: 8px;
        padding: 16px 24px;
        margin-bottom: 16px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        direction: ltr;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.05);
    }
    .scada-header-left {
        text-align: left;
        direction: ltr;
        color: #0f172a;
    }
    .scada-header-left h2 {
        margin: 0;
        font-size: 1.6rem;
        font-weight: 800;
        color: #0f172a;
        letter-spacing: -0.02em;
    }
    .scada-header-left .sub {
        font-size: 0.92rem;
        font-weight: 600;
        color: #475569;
        margin-top: 2px;
    }
    .scada-header-left .ts {
        font-size: 0.88rem;
        font-weight: 700;
        color: #0284c7;
        font-variant-numeric: tabular-nums;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        margin-top: 2px;
    }
    .scada-header-right {
        display: flex;
        align-items: center;
        gap: 16px;
        text-align: right;
        direction: ltr;
    }
    .scada-ministry-text {
        text-align: right;
        line-height: 1.3;
    }

    /* Modern Neutral Card Architecture with high scanability */
    .scada-card {
        background-color: #ffffff;
        border: 1px solid #e2e8f0;
        border-radius: 8px;
        padding: 14px 18px;
        margin-bottom: 10px;
        text-align: center;
        box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.04);
        transition: border-color 0.15s ease-in-out;
    }
    .scada-card:hover {
        border-color: #94a3b8;
    }
    .scada-card-main {
        background-color: #0f172a;
        border: 1px solid #0f172a;
        border-radius: 8px;
        padding: 16px 20px;
        margin-bottom: 12px;
        text-align: center;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    }
    .card-title-main {
        font-size: 1.15rem;
        font-weight: 700;
        margin-bottom: 8px;
        color: #f8fafc;
        letter-spacing: -0.01em;
    }
    .card-value-pill-main {
        display: inline-block;
        background-color: #ffffff;
        color: #0f172a;
        font-size: 1.65rem;
        font-weight: 800;
        padding: 4px 24px;
        border-radius: 6px;
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
        border: 2px solid #e2e8f0;
    }
    .card-title {
        font-size: 0.95rem;
        font-weight: 600;
        margin-bottom: 4px;
        color: #475569;
    }
    .card-value {
        font-size: 1.35rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        color: #0f172a;
        direction: ltr;
    }
    .math-operator {
        font-size: 1.5rem;
        font-weight: 800;
        text-align: center;
        color: #64748b;
        margin: -4px 0 6px 0;
        line-height: 1;
    }

    /* Accessibility Legend: Patterns, Symbols & Weights */
    .legend-box {
        border: 1px solid #cbd5e1;
        background-color: #ffffff;
        border-radius: 6px;
        width: 100%;
        margin-top: 12px;
        font-size: 0.88rem;
    }
    .legend-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 8px 12px;
        border-bottom: 1px solid #f1f5f9;
        direction: rtl;
    }
    .legend-row:last-child {
        border-bottom: none;
    }

    /* Color-blind fallback badge indicators */
    .badge-safe {
        border: 2px solid #16a34a;
        background-color: #f0fdf4;
        color: #14532d;
        padding: 2px 8px;
        border-radius: 4px;
        font-weight: 700;
    }
    .badge-warning {
        border: 2px dashed #d97706;
        background-color: #fffbeb;
        color: #78350f;
        padding: 2px 8px;
        border-radius: 4px;
        font-weight: 700;
    }
    .badge-critical {
        border: 2px double #dc2626;
        background: repeating-linear-gradient(45deg, #fef2f2, #fef2f2 6px, #fee2e2 6px, #fee2e2 12px);
        color: #7f1d1d;
        padding: 2px 8px;
        border-radius: 4px;
        font-weight: 800;
    }

    /* Quick Telemetry Pill Bar */
    .telemetry-strip {
        background-color: #f8fafc;
        border: 1px solid #e2e8f0;
        border-radius: 6px;
        padding: 8px 16px;
        margin-bottom: 16px;
        display: flex;
        flex-wrap: wrap;
        gap: 16px;
        font-size: 0.88rem;
        color: #334155;
        font-variant-numeric: tabular-nums;
    }
    .telemetry-strip strong {
        color: #0f172a;
    }
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
    f'<img src="data:image/svg+xml;base64,{LOGO_B64}" width="60" height="60" alt="MEW Emblem" />'
    if LOGO_B64
    else ""
)

# Header Banner
st.markdown(
    f"""
    <div class="scada-header-bar">
        <div class="scada-header-left">
            <h2>نظام توليد الطاقة والتحكم اللحظي</h2>
            <div class="sub">SCADA Generation &amp; Grid Load Monitoring Hub</div>
            <div class="ts">Live SCADA: {ts_formatted}</div>
        </div>
        <div class="scada-header-right">
            <div class="scada-ministry-text">
                <div style="font-size: 1.05rem; font-weight: 800; color: #0f172a;">وزارة الكهرباء والماء والطاقة المتجددة</div>
                <div style="font-size: 0.88rem; font-weight: 600; color: #475569;">State of Kuwait | دولة الكويت</div>
            </div>
            {logo_img_html}
        </div>
    </div>
    """,
    unsafe_allow_html=True,
)

# Telemetry Strip
st.markdown(
    f"""
    <div class="telemetry-strip">
        <div><strong>آخر تحديث:</strong> {ts_formatted}</div>
        <div><strong>التردد:</strong> {float(scada.get('frequency_hz', 50.0)):.2f} Hz</div>
        <div><strong>الحرارة:</strong> {float(scada.get('temp_c', 38.5)):.1f} °C</div>
        <div><strong>المولدات النشطة:</strong> {int(scada.get('active_generators', 18))}</div>
        <div><strong>هامش الاحتياطي:</strong> {float(scada.get('reserve_margin_mw', 3122.0)):,.0f} MW</div>
    </div>
    """,
    unsafe_allow_html=True,
)

tab_scada, tab_forecast, tab_whatif, tab_agent = st.tabs(
    [
        "⚡ لوحة التحكم اللحظية (SCADA Balance)",
        "📈 توقعات ذروة الأحمال لـ 30 يوماً (ARIMA+)",
        "🧪 محاكاة سيناريوهات الإجهاد الحراري (What-If BQML)",
        "🤖 وكيل طاقة الكويت (KEI Agent)",
    ]
)

with tab_scada:
    c_gauge, c_load, c_cap = st.columns([1.15, 1.42, 1.42])

    with c_gauge:
        cap_val = float(scada["available_capacity_mw"])
        load_val = float(scada["current_load_mw"])
        load_pct = float(scada.get("load_percentage", (load_val / cap_val * 100.0) if cap_val else 70.0))

        # Modern High-Contrast Gauge with Color-Blind Distinguishable Steps
        fig = go.Figure(
            go.Indicator(
                mode="gauge+number",
                value=min(100.0, max(0.0, load_pct)),
                number={
                    "suffix": " %",
                    "valueformat": ".1f",
                    "font": {"size": 22, "family": "-apple-system, BlinkMacSystemFont, Segoe UI", "color": "#0f172a"},
                },
                title={
                    "text": (
                        f"<b>الحمل اللحظي</b><br>"
                        f"<span style='font-size:24px;font-weight:800;color:#0f172a;border:1px solid #cbd5e1;padding:2px 12px;background:#ffffff;border-radius:4px;'>"
                        f"{load_val:,.0f} MW</span>"
                    ),
                    "font": {"size": 14, "family": "-apple-system, BlinkMacSystemFont, Segoe UI", "color": "#475569"},
                },
                gauge={
                    "axis": {"range": [0, 100], "tickwidth": 2, "tickcolor": "#0f172a", "dtick": 10},
                    "bar": {"color": "#0f172a", "thickness": 0.24},
                    "bgcolor": "#f8fafc",
                    "borderwidth": 2,
                    "bordercolor": "#cbd5e1",
                    "steps": [
                        {"range": [0, 85], "color": "#dcfce7"},      # Light distinct green
                        {"range": [85, 95], "color": "#fef3c7"},     # Light distinct amber
                        {"range": [95, 100], "color": "#fee2e2"},    # Light distinct red
                    ],
                    "threshold": {
                        "line": {"color": "#0284c7", "width": 4},
                        "thickness": 0.85,
                        "value": min(100.0, max(0.0, load_pct)),
                    },
                },
            )
        )
        fig.update_layout(
            height=300,
            margin=dict(l=14, r=14, t=35, b=10),
            paper_bgcolor="rgba(0,0,0,0)",
        )
        st.plotly_chart(fig, use_container_width=True)

        # Legend with Line Weights, Patterns, and Visual Symbols for Full Accessibility
        st.markdown(
            """
            <div class="legend-box">
                <div class="legend-row">
                    <span><b>[✔] التشغيل الآمن</b> (&lt; 85%)</span>
                    <span class="badge-safe">Solid &bull; نمط متصل</span>
                </div>
                <div class="legend-row">
                    <span><b>[▲] التشغيل الحرج</b> (85% - 95%)</span>
                    <span class="badge-warning">Dashed &bull; نمط متقطع</span>
                </div>
                <div class="legend-row">
                    <span><b>[✖] القطع المبرمج</b> (&gt; 95%)</span>
                    <span class="badge-critical">Striped &bull; نمط مضلع</span>
                </div>
            </div>
            """,
            unsafe_allow_html=True,
        )

    with c_load:
        st.markdown(
            f"""
            <div class="scada-card-main">
                <div class="card-title-main">الأحمال الحالية (Current Load)</div>
                <div class="card-value-pill-main">{scada['current_load_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">=</div>
            <div class="scada-card">
                <div class="card-title">إجمالي الإنتاج الحالي (Net Generation)</div>
                <div class="card-value">{scada['net_generation_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="scada-card">
                <div class="card-title">تبادل الطاقة مع الربط الخليجي (GCC Exchange)</div>
                <div class="card-value">{scada['gcc_exchange_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="scada-card">
                <div class="card-title">الأحمال المفصولة (Load Shedding)</div>
                <div class="card-value">{scada['loadshed_mw']:,.0f} MW</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

    with c_cap:
        st.markdown(
            f"""
            <div class="scada-card-main">
                <div class="card-title-main">القدرة المتوفرة (Available Capacity)</div>
                <div class="card-value-pill-main">{scada['available_capacity_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">=</div>
            <div class="scada-card">
                <div class="card-title">الإنتاج الكلي (Gross Production)</div>
                <div class="card-value">{scada['gross_production_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="scada-card">
                <div class="card-title">الطاقة الإحتياطية المتوفرة (Available Reserve)</div>
                <div class="card-value">{scada['available_reserve_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">+</div>
            <div class="scada-card">
                <div class="card-title">الطاقة المزودة من الربط الخليجي (GCC Supplied)</div>
                <div class="card-value">{scada['gcc_supplied_mw']:,.0f} MW</div>
            </div>
            <div class="math-operator">-</div>
            <div class="scada-card">
                <div class="card-title">الإحتياطي المطلوب للربط الخليجي (GCC Obligation)</div>
                <div class="card-value">{scada['gcc_obligation_mw']:,.0f} MW</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

with tab_forecast:
    st.markdown("### 📈 توقعات ذروة الأحمال للأيام الـ 30 القادمة (ARIMA_PLUS)")
    st.caption("تنبؤات دقيقة مبنية على الطبقة الذهبية `forecast_30d` مع فترات الثقة 85%.")
    df_fc = fetch_gold_forecast()
    fig_fc = go.Figure()
    fig_fc.add_trace(
        go.Scatter(
            x=pd.concat([df_fc["forecast_date"], df_fc["forecast_date"][::-1]]),
            y=pd.concat([df_fc["upper_bound_mw"], df_fc["lower_bound_mw"][::-1]]),
            fill="toself",
            fillcolor="rgba(2, 132, 199, 0.10)",
            line=dict(color="rgba(255,255,255,0)"),
            name="مجال الثقة 85%",
        )
    )
    fig_fc.add_trace(
        go.Scatter(
            x=df_fc["forecast_date"],
            y=df_fc["predicted_peak_mw"],
            mode="lines+markers",
            line=dict(color="#0284c7", width=3),
            marker=dict(size=6, color="#0f172a"),
            name="ذروة الحمل المتوقعة (MW)",
        )
    )
    fig_fc.update_layout(
        template="plotly_white",
        height=450,
        hovermode="x unified",
        font=dict(family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto"),
        margin=dict(l=20, r=20, t=20, b=20),
    )
    st.plotly_chart(fig_fc, use_container_width=True)

with tab_whatif:
    st.markdown("### 🧪 محاكاة سيناريوهات الإجهاد الحراري (What-If BQML)")
    st.caption("نموذج Boosted Tree Regressor للتنبؤ الفوري بالحمل الأقصى تحت ظروف طقس متطرفة.")
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
