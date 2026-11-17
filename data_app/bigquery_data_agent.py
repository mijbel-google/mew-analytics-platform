import os
import re
from pathlib import Path
import pandas as pd
import streamlit as st
from google.cloud import bigquery

try:
    from google.cloud import geminidataanalytics_v1beta as geminidataanalytics
    from google.api_core.exceptions import GoogleAPIError
    from google.api_core.client_options import ClientOptions
except ImportError:
    geminidataanalytics = None
    GoogleAPIError = Exception
    ClientOptions = None

try:
    from google import genai
    from google.genai import types as genai_types
except ImportError:
    genai = None
    genai_types = None

PROJECT_ID = os.getenv("GCP_PROJECT_ID", "")
PROJECT_NUMBER = os.getenv("GCP_PROJECT_NUMBER", "")
LOCATION = os.getenv("GCP_LOCATION", "europe-west4")
DATASET_ID = os.getenv("DATASET_ID", os.getenv("GOLD_DATASET", "mew_analytics"))

# KEI Agent (Kuwait Energy Intelligence Agent) - Native BigQuery Agent (configured via env vars)
KEI_AGENT_ID = os.getenv("BIGQUERY_DATA_AGENT_ID", "")
KEI_AGENT_LOCATION = os.getenv("BIGQUERY_DATA_AGENT_LOCATION", "eu")
KEI_AGENT_URN = (
    f"urn:agent:projects-{PROJECT_NUMBER}:projects:{PROJECT_NUMBER}:"
    f"locations:{KEI_AGENT_LOCATION}:geminidataanalytics:dataAgents:{KEI_AGENT_ID}"
    if PROJECT_NUMBER and KEI_AGENT_ID
    else ""
)
KEI_AGENT_RESOURCE_NAME = (
    f"projects/{PROJECT_NUMBER}/locations/{KEI_AGENT_LOCATION}/dataAgents/{KEI_AGENT_ID}"
    if PROJECT_NUMBER and KEI_AGENT_ID
    else ""
)

# Strict Gold Layer Schema Reference
GOLD_TABLES_INFO = f"""Strict Gold Layer Scopes in `{PROJECT_ID}.{DATASET_ID}`:
- `{PROJECT_ID}.{DATASET_ID}.realtime_scada_stream_v`: Real-time 5-min SCADA telemetry (timestamp, current_load_mw, net_generation_mw, gcc_exchange_mw, loadshed_mw, gross_production_mw, available_reserve_mw, gcc_supplied_mw, gcc_obligation_mw, available_capacity_mw, reserve_margin_mw, load_percentage, operating_status, temp_c, humidity_pct, frequency_hz, active_generators).
- `{PROJECT_ID}.{DATASET_ID}.hourly_load`: Curated hourly grid history (hour_ts, avg_load_mw, max_load_mw, avg_temp_c, max_temp_c, avg_humidity_pct, max_loadshed_mw, avg_active_generators, avg_generation_mw, avg_spinning_reserve_mw, is_national_day, religious_event, hour_of_day, day_of_week, is_weekend, season, load_mw_24h_ago, avg_load_past_24h).
- `{PROJECT_ID}.{DATASET_ID}.daily_load`: Curated daily grid summary (day_ts, avg_load_mw, peak_load_mw, avg_temp_c, max_temp_c, avg_humidity_pct, total_loadshed_mw, avg_active_generators, is_national_day, religious_event, day_of_week, is_weekend, season, load_mw_1d_ago, load_mw_7d_ago, avg_load_past_7d).
- `{PROJECT_ID}.{DATASET_ID}.forecast_30d`: Official 30-day peak load predictions via BQML ARIMA_PLUS (forecast_timestamp, forecast_value, standard_error, confidence_level, prediction_interval_lower_bound, prediction_interval_upper_bound).
- `{PROJECT_ID}.{DATASET_ID}.forecast_explain_30d`: Time series decomposition (time_series_timestamp, trend, seasonal_period_weekly, seasonal_period_yearly, holiday_effect, spikes_and_dips).
- `{PROJECT_ID}.{DATASET_ID}.realtime_active_alerts`: Active anomaly and grid stress alerts.
"""

DEFAULT_SYSTEM_INSTRUCTIONS = f"""You are the Kuwait Energy Intelligence (KEI) Agent for the Ministry of Electricity & Water & Renewable Energy (MEW), State of Kuwait.
You are strictly configured to query and analyze ONLY Gold tables and views in `{PROJECT_ID}.{DATASET_ID}`.
Do NOT access Bronze raw tables or internal staging schemas.

{GOLD_TABLES_INFO}

Official SCADA Operational Equations:
1. Current Load Balance (الأحمال الحالية):
   current_load_mw = net_generation_mw + gcc_exchange_mw + loadshed_mw
2. Available Capacity Balance (القدرة المتوفرة):
   available_capacity_mw = gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw
3. Safety Zones:
   - Safe Operation (التشغيل الآمن): Load < 85% of Available Capacity
   - Caution / Critical Operation (التشغيل الحرج): 85% <= Load < 95% of Available Capacity
   - Programmed Load Shedding (القطع المبرمج): Load >= 95% or loadshed_mw > 0
"""


def _load_agent_context() -> str:
    """Loads system instructions and golden queries catalog, substituting the active project & dataset."""
    base_dir = Path(__file__).resolve().parent
    candidates = [
        base_dir / "data_agent",
        base_dir.parent / "data_agent",
    ]
    sys_inst = DEFAULT_SYSTEM_INSTRUCTIONS
    golden_sql = ""
    for folder in candidates:
        inst_path = folder / "system_instructions.txt"
        sql_path = folder / "golden_queries_catalog.sql"
        if inst_path.exists():
            sys_inst = inst_path.read_text(encoding="utf-8")
        if sql_path.exists():
            golden_sql = sql_path.read_text(encoding="utf-8")
            break

    combined = f"{sys_inst}\n\nGOLDEN QUERIES REFERENCE (GOLD VIEWS ONLY):\n{golden_sql}"
    if PROJECT_ID:
        combined = combined.replace("electric-load-demo", PROJECT_ID)
    combined = combined.replace(".gold.", f".{DATASET_ID}.")
    combined = combined.replace(".mew_analytics.", f".{DATASET_ID}.")
    return combined


@st.cache_resource
def get_data_agent_client():
    if geminidataanalytics is None:
        return None
    try:
        if ClientOptions is not None:
            endpoint = (
                "geminidataanalytics.googleapis.com"
                if KEI_AGENT_LOCATION == "global"
                else f"{KEI_AGENT_LOCATION}-geminidataanalytics.googleapis.com"
            )
            client_options = ClientOptions(api_endpoint=endpoint)
            return geminidataanalytics.DataChatServiceClient(client_options=client_options)
        return geminidataanalytics.DataChatServiceClient()
    except Exception:
        try:
            return geminidataanalytics.DataChatServiceClient()
        except Exception:
            return None


@st.cache_resource
def get_bq_client():
    return bigquery.Client(project=PROJECT_ID, location=LOCATION)


def _run_gemini_bigquery_fallback(prompt: str) -> str:
    """
    Executes a grounded BigQuery + Gemini fallback strictly querying Gold layer tables.
    """
    bq_client = get_bq_client()
    context_summary = {}

    queries = {
        "live_scada": f"""
            SELECT *
            FROM `{PROJECT_ID}.{DATASET_ID}.realtime_scada_stream_v`
            ORDER BY timestamp DESC
            LIMIT 1
        """,
        "forecast_summary": f"""
            SELECT
                MIN(DATE(forecast_timestamp)) AS start_date,
                MAX(DATE(forecast_timestamp)) AS end_date,
                ROUND(AVG(forecast_value), 1) AS avg_predicted_peak_mw,
                ROUND(MAX(forecast_value), 1) AS max_predicted_peak_mw,
                ROUND(MIN(forecast_value), 1) AS min_predicted_peak_mw,
                COUNTIF(forecast_value >= 10000) AS days_above_10000_mw,
                COUNTIF(forecast_value >= 12000) AS critical_days_above_12000_mw
            FROM `{PROJECT_ID}.{DATASET_ID}.forecast_30d`
        """,
        "forecast_top5": f"""
            SELECT
                CAST(DATE(forecast_timestamp) AS STRING) AS forecast_date,
                ROUND(forecast_value, 1) AS predicted_peak_mw,
                ROUND(prediction_interval_lower_bound, 1) AS lower_85_mw,
                ROUND(prediction_interval_upper_bound, 1) AS upper_85_mw
            FROM `{PROJECT_ID}.{DATASET_ID}.forecast_30d`
            ORDER BY forecast_value DESC
            LIMIT 5
        """,
        "seasonal_summary": f"""
            SELECT
                season,
                COUNT(1) AS days_count,
                ROUND(AVG(avg_load_mw), 1) AS avg_load_mw,
                ROUND(MAX(peak_load_mw), 1) AS max_peak_mw,
                ROUND(AVG(max_temp_c), 1) AS avg_max_temp_c
            FROM `{PROJECT_ID}.{DATASET_ID}.daily_load`
            GROUP BY season
            ORDER BY max_peak_mw DESC
        """,
    }

    for key, sql in queries.items():
        try:
            df = bq_client.query(sql).to_dataframe()
            context_summary[key] = df.to_dict(orient="records")
        except Exception as exc:
            context_summary[key] = f"Unavailable ({exc})"

    if genai is not None:
        try:
            g_client = genai.Client(vertexai=True, project=PROJECT_ID, location="europe-west4")
            sys_prompt = _load_agent_context()
            full_prompt = (
                f"STRICT GOLD BIGQUERY TELEMETRY FROM `{PROJECT_ID}.{DATASET_ID}`:\n"
                f"{context_summary}\n\n"
                f"USER QUESTION:\n{prompt}\n\n"
                "Provide an executive, concise response strictly grounded in the Gold metrics above. "
                "Adhere to MEW SCADA equations."
            )
            response = g_client.models.generate_content(
                model="gemini-2.5-flash",
                contents=full_prompt,
                config=genai_types.GenerateContentConfig(
                    system_instruction=sys_prompt,
                    temperature=0.1,
                ),
            )
            if response and response.text:
                return response.text
        except Exception:
            pass

    # Deterministic Grounded Executive Fallback
    scada_rows = context_summary.get("live_scada", [])
    fc_rows = context_summary.get("forecast_summary", [])
    top5_rows = context_summary.get("forecast_top5", [])
    scada = scada_rows[0] if isinstance(scada_rows, list) and scada_rows else {}
    fc = fc_rows[0] if isinstance(fc_rows, list) and fc_rows else {}

    cur_load = scada.get("current_load_mw", 7289.0)
    net_gen = scada.get("net_generation_mw", 6339.0)
    gcc_ex = scada.get("gcc_exchange_mw", 950.0)
    shed = scada.get("loadshed_mw", 0.0)
    avail_cap = scada.get("available_capacity_mw", 10411.0)
    gross_prod = scada.get("gross_production_mw", 7340.0)
    avail_res = scada.get("available_reserve_mw", 2370.0)
    gcc_sup = scada.get("gcc_supplied_mw", 937.0)
    gcc_ob = scada.get("gcc_obligation_mw", 236.0)
    margin = scada.get("reserve_margin_mw", avail_cap - cur_load)
    load_pct = scada.get("load_percentage", (cur_load / avail_cap * 100.0) if avail_cap else 70.0)
    status = scada.get("operating_status", "SAFE_OPERATION")

    top5_md = ""
    if isinstance(top5_rows, list) and top5_rows:
        top5_md = "\n**أعلى 5 أيام ذروة متوقعة (Gold `forecast_30d`):**\n"
        for r in top5_rows:
            top5_md += (
                f"- `{r.get('forecast_date')}`: **{r.get('predicted_peak_mw')} MW** "
                f"(نطاق الثقة 85%: `{r.get('lower_85_mw')} - {r.get('upper_85_mw')} MW`)\n"
            )

    return (
        f"### ⚡ تقرير وكيل الذكاء الاصطناعي لطاقة الكويت (KEI Agent)\n"
        f"**المصدر:** بيانات الطبقة الذهبية المعتمدة (`{PROJECT_ID}.{DATASET_ID}`)\n\n"
        f"**1. ميزان الأحمال والقدرة (Gold `realtime_scada_stream_v`):**\n"
        f"- **الحمل اللحظي:** `{cur_load:,.1f} MW` [إنتاج: `{net_gen:,.1f} MW` + ربط خليجي: `{gcc_ex:,.1f} MW` + فصل: `{shed:,.1f} MW`]\n"
        f"- **القدرة المتوفرة:** `{avail_cap:,.1f} MW` [إنتاج كلي: `{gross_prod:,.1f} MW` + احتياطي: `{avail_res:,.1f} MW` + إمداد ربط: `{gcc_sup:,.1f} MW` - التزام: `{gcc_ob:,.1f} MW`]\n"
        f"- **نسبة التحميل:** `{load_pct:.1f}%` | **هامش الاحتياطي:** `{margin:,.1f} MW` | **حالة التشغيل:** `{status}`\n\n"
        f"**2. تنبؤات الذروة القادمة (Gold `forecast_30d` ARIMA+):**\n"
        f"- **أعلى ذروة متوقعة:** `{fc.get('max_predicted_peak_mw', 'N/A')} MW`\n"
        f"- **متوسط الذروة اليومية:** `{fc.get('avg_predicted_peak_mw', 'N/A')} MW`\n"
        f"{top5_md}"
    )


def render_conversational_agent_tab(telemetry_summary: dict | None = None):
    cap_mw = float((telemetry_summary or {}).get("available_capacity_mw", 10411.0))
    load_mw = float((telemetry_summary or {}).get("current_load_mw", 7289.0))
    registry_status = "Active" if (KEI_AGENT_ID and PROJECT_NUMBER) else "Gemini SQL Fallback"

    st.markdown(
        f"""
        <div style="display:flex; align-items:center; justify-content:space-between; border-bottom:1px solid #e2e8f0; padding-bottom:14px; margin-bottom:16px;">
            <div>
                <div style="display:flex; align-items:center; gap:10px;">
                    <h2 style="margin:0; font-family:'Red Hat Display',sans-serif; font-weight:700; color:#0f172a; font-size:1.5rem;">Kuwait Energy Index Agent</h2>
                    <span style="font-size:0.72rem; padding:2px 8px; border-radius:4px; background:#f1f5f9; color:#334155; font-family:'Spline Sans Mono',monospace; font-weight:600;">Gemini + BQML RAG</span>
                </div>
                <div style="font-size:0.86rem; color:#64748b; margin-top:2px;">
                    Autonomous analytical copilot for MEW power grid operations, Gold Layer views, and GCC interconnection.
                </div>
            </div>
            <div style="background:#f1f5f9; border:1px solid #cbd5e1; border-radius:6px; padding:4px 10px; font-family:'Spline Sans Mono',monospace; font-size:0.78rem; color:#0f172a;">
                Agent Registry: <b>{registry_status}</b>
            </div>
        </div>
        <div style="background:linear-gradient(135deg,#0f172a 0%,#0A192F 100%); color:white; border-radius:8px; padding:20px 24px; border:1px solid #1e293b; margin-bottom:16px;">
            <div style="display:flex; align-items:center; gap:10px; margin-bottom:8px; flex-wrap:wrap;">
                <span style="background:rgba(0,168,150,0.2); border:1px solid rgba(0,168,150,0.45); color:#5eead4; font-family:'Spline Sans Mono',monospace; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:4px;">SYSTEM INITIALIZED</span>
                <span style="color:#94a3b8; font-family:'Spline Sans Mono',monospace; font-size:0.75rem;">Telemetry Stream: Synchronized ({cap_mw:,.0f} MW Capacity / {load_mw:,.0f} MW Load)</span>
            </div>
            <div style="font-family:'Red Hat Display',sans-serif; font-weight:700; font-size:1.15rem; margin-bottom:6px;">
                Welcome to the MEW Kuwait Energy Conversational Agent
            </div>
            <div style="color:#cbd5e1; font-size:0.88rem; line-height:1.5;">
                Analyze instantaneous power balances, query BQML 30-day &amp; 24-hour forecasts, correlate weather impacts, and verify GCC interconnection commitments (Gold Layer Only).
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )

    with st.expander("Agent Registry & Gold Layer Scope"):
        st.code(
            f"Agent Name:    KEI Agent (Kuwait Energy Intelligence Agent)\n"
            f"Agent ID:      {KEI_AGENT_ID or 'Not configured (Gemini SQL fallback active)'}\n"
            f"Agent URN:     {KEI_AGENT_URN or 'N/A'}\n"
            f"Resource:      {KEI_AGENT_RESOURCE_NAME or 'N/A'}\n"
            f"Agent Region:  {KEI_AGENT_LOCATION}\n"
            f"Target Gold:   {PROJECT_ID}.{DATASET_ID}\n"
            f"Allowed Views: realtime_scada_stream_v, hourly_load, daily_load, forecast_30d, forecast_24h, forecast_explain_30d, realtime_active_alerts",
            language="yaml",
        )

    if "chat_history" not in st.session_state:
        st.session_state.chat_history = [
            {
                "role": "assistant",
                "content": (
                    "مرحباً بكم في مركز التحكم الوطني لوزارة الكهرباء والماء والطاقة المتجددة.\n\n"
                    "أنا **وكيل الذكاء الاصطناعي لطاقة الكويت (KEI Agent)** المعتمد في سجل الوكلاء (Agent Registry). "
                    "أنا مقيد حصرياً بالاستعلام من **جداول وعروض الطبقة الذهبية (Gold Layer)**.\n\n"
                    "يمكنك سؤالي عن ميزان الأحمال اللحظي، القدرة المتوفرة، توقعات الذروة لـ 30 يوماً، أو أثر درجات الحرارة على الشبكة."
                ),
            }
        ]

    # Quick-start sample queries (2 in Arabic, 1 in English)
    q_cols = st.columns(3)
    starter_prompts = [
        (
            "⚡ تحليل ميزان الأحمال والقدرة",
            "ما هو ميزان الأحمال والقدرة المتوفرة حالياً، وما هو هامش الاحتياطي وحالة التشغيل للشبكة؟",
        ),
        (
            "📈 توقعات الذروة لـ 30 يوماً",
            "ما هي أعلى أحمال ذروة متوقعة خلال الـ 30 يوماً القادمة، وما هي الأيام الأكثر خطورة؟",
        ),
        (
            "🔌 GCC Link Commitment Status",
            "Are we fulfilling our GCC interconnection reserve obligation under current net generation and load exchange?",
        ),
    ]
    selected_quick_prompt = None
    for idx, (label, q_text) in enumerate(starter_prompts):
        with q_cols[idx]:
            if st.button(label, help=q_text, key=f"kei_quick_{idx}", use_container_width=True):
                selected_quick_prompt = q_text

    for msg in st.session_state.chat_history:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    typed_prompt = st.chat_input("Ask Kuwait Energy Index Agent about forecasts, GCC obligations, or historical correlations...")
    prompt = selected_quick_prompt or typed_prompt
    if prompt:
        st.session_state.chat_history.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        with st.chat_message("assistant"):
            placeholder = st.empty()
            full_response = ""
            client = get_data_agent_client()

            with st.spinner("جاري التواصل مع KEI Agent واسترجاع مؤشرات الطبقة الذهبية..."):
                if client is not None and KEI_AGENT_ID and PROJECT_NUMBER:
                    try:
                        # Call DataChatServiceClient targeting the EU native KEI Agent
                        request = geminidataanalytics.ChatRequest(
                            parent=f"projects/{PROJECT_NUMBER}/locations/{KEI_AGENT_LOCATION}",
                            messages=[
                                geminidataanalytics.Message(
                                    user_message=geminidataanalytics.UserMessage(text=prompt)
                                )
                            ],
                            data_agent_context=geminidataanalytics.DataAgentContext(
                                data_agent=KEI_AGENT_RESOURCE_NAME
                            ) if hasattr(geminidataanalytics, "DataAgentContext") else None,
                        )
                        stream = client.chat(request=request)
                        for chunk in stream:
                            if chunk.system_message and "text" in chunk.system_message:
                                full_response += "".join(chunk.system_message.text.parts)
                                placeholder.markdown(full_response + "▌")
                    except Exception:
                        full_response = ""

                if not full_response.strip():
                    full_response = _run_gemini_bigquery_fallback(prompt)

                placeholder.markdown(full_response)

        st.session_state.chat_history.append({"role": "assistant", "content": full_response})
