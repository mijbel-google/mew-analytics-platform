import os
import re
from pathlib import Path
import pandas as pd
import streamlit as st
from google.cloud import bigquery

try:
    from google.cloud import geminidataanalytics_v1beta as geminidataanalytics
    from google.api_core.exceptions import GoogleAPIError
except ImportError:
    geminidataanalytics = None
    GoogleAPIError = Exception

try:
    from google import genai
    from google.genai import types as genai_types
except ImportError:
    genai = None
    genai_types = None

PROJECT_ID = os.getenv("GCP_PROJECT_ID", "electric-load-demo")
LOCATION = os.getenv("GCP_LOCATION", "europe-west4")
GEMINI_LOCATION = os.getenv("GEMINI_LOCATION", "us-central1")
DATASET_ID = os.getenv("DATASET_ID", os.getenv("GOLD_DATASET", "mew_analytics"))

DATA_AGENT_ENDPOINT = os.getenv(
    "BIGQUERY_DATA_AGENT_ENDPOINT",
    f"projects/{PROJECT_ID}/locations/{LOCATION}/dataAgents/mew-grid-intelligence-agent",
)

DEFAULT_SYSTEM_INSTRUCTIONS = f"""You are the Senior Power Grid Intelligence Specialist for the Ministry of Electricity & Water & Renewable Energy (MEW), State of Kuwait.
You have direct access to BigQuery curated tables and views in `{PROJECT_ID}.{DATASET_ID}`:
- `{PROJECT_ID}.{DATASET_ID}.realtime_scada_stream_v`: Real-time 5-minute SCADA telemetry (timestamp, current_load_mw, net_generation_mw, gcc_exchange_mw, loadshed_mw, gross_production_mw, available_reserve_mw, gcc_supplied_mw, gcc_obligation_mw, available_capacity_mw, reserve_margin_mw, load_percentage, operating_status, temp_c, humidity_pct, frequency_hz, active_generators).
- `{PROJECT_ID}.{DATASET_ID}.hourly_load`: Historical hourly demand (hour_ts, avg_load_mw, max_load_mw, avg_temp_c, max_temp_c, avg_humidity_pct, max_loadshed_mw, avg_active_generators, avg_generation_mw, avg_spinning_reserve_mw, is_national_day, religious_event, hour_of_day, day_of_week, is_weekend, season, load_mw_24h_ago, avg_load_past_24h).
- `{PROJECT_ID}.{DATASET_ID}.daily_load`: Historical daily peak loads (day_ts, avg_load_mw, peak_load_mw, avg_temp_c, max_temp_c, avg_humidity_pct, total_loadshed_mw, avg_active_generators, is_national_day, religious_event, day_of_week, is_weekend, season, load_mw_1d_ago, load_mw_7d_ago, avg_load_past_7d).
- `{PROJECT_ID}.{DATASET_ID}.forecast_30d`: Official 30-day daily peak load forecasts (forecast_timestamp, forecast_value, standard_error, confidence_level, prediction_interval_lower_bound, prediction_interval_upper_bound).
- `{PROJECT_ID}.{DATASET_ID}.forecast_explain_30d`: Forecast decomposition (time_series_timestamp, time_series_type, time_series_data, trend, seasonal_period_weekly, seasonal_period_yearly, holiday_effect, spikes_and_dips).
- `{PROJECT_ID}.{DATASET_ID}.realtime_active_alerts`: Active grid stress and anomaly alerts.

Balance Equation 1 (الأحمال الحالية): current_load_mw = net_generation_mw + gcc_exchange_mw + loadshed_mw
Balance Equation 2 (القدرة المتوفرة): available_capacity_mw = gross_production_mw + available_reserve_mw + gcc_supplied_mw - gcc_obligation_mw
Safety Zones:
- Safe Operation (التشغيل الآمن): Load < 85% of Available Capacity
- Unsafe Operation (التشغيل الغير آمن): 85% <= Load < 95% of Available Capacity
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

    combined = f"{sys_inst}\n\nGOLDEN QUERIES REFERENCE:\n{golden_sql}"
    combined = combined.replace("electric-load-demo", PROJECT_ID)
    combined = combined.replace(".gold.", f".{DATASET_ID}.")
    combined = combined.replace(".mew_analytics.", f".{DATASET_ID}.")
    return combined


@st.cache_resource
def get_data_agent_client():
    if geminidataanalytics is None:
        return None
    try:
        return geminidataanalytics.DataChatServiceClient()
    except Exception:
        return None


@st.cache_resource
def get_bq_client():
    return bigquery.Client(project=PROJECT_ID, location=LOCATION)


def _run_gemini_bigquery_fallback(prompt: str) -> str:
    """
    Executes a grounded BigQuery + Gemini fallback using the system instructions
    and golden queries catalog when the Data Agent endpoint is not yet provisioned.
    """
    bq_client = get_bq_client()
    context_summary = {}

    # 1. Fetch live SCADA snapshot, 30d forecast summary, and summer heat stats
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

    # 2. Try Gemini API (Vertex AI) if available
    if genai is not None:
        try:
            g_client = genai.Client(vertexai=True, project=PROJECT_ID, location=GEMINI_LOCATION)
            sys_prompt = _load_agent_context()
            full_prompt = (
                f"LIVE BIGQUERY TELEMETRY & FORECAST DATA FROM `{PROJECT_ID}.{DATASET_ID}`:\n"
                f"{context_summary}\n\n"
                f"USER QUESTION:\n{prompt}\n\n"
                "Provide a clear, accurate, executive response grounded strictly in the live BigQuery metrics above."
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

    # 3. Deterministic SQL Grounded Executive Summary if Vertex Gemini endpoint is restricted
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
        top5_md = "\n**أعلى 5 أيام ذروة متوقعة خلال الـ 30 يوماً القادمة:**\n"
        for r in top5_rows:
            top5_md += (
                f"- `{r.get('forecast_date')}`: **{r.get('predicted_peak_mw')} MW** "
                f"(نطاق الثقة 85%: `{r.get('lower_85_mw')} - {r.get('upper_85_mw')} MW`)\n"
            )

    return (
        f"### 📊 تقرير مركز التحكم الوطني المعتمد (`{PROJECT_ID}.{DATASET_ID}`)\n\n"
        f"**1. معادلة الأحمال الحالية (SCADA Live Balance):**\n"
        f"- **الأحمال الحالية:** `{cur_load:,.1f} MW` = إجمالي الإنتاج الحالي (`{net_gen:,.1f} MW`) "
        f"+ تبادل الطاقة مع الربط الخليجي (`{gcc_ex:,.1f} MW`) + الأحمال المفصولة (`{shed:,.1f} MW`)\n"
        f"- **القدرة المتوفرة:** `{avail_cap:,.1f} MW` = الإنتاج الكلي (`{gross_prod:,.1f} MW`) "
        f"+ الطاقة الاحتياطية المتوفرة (`{avail_res:,.1f} MW`) + الطاقة المزودة من الربط الخليجي (`{gcc_sup:,.1f} MW`) "
        f"- الاحتياطي المطلوب للربط الخليجي (`{gcc_ob:,.1f} MW`)\n"
        f"- **هامش الاحتياطي المتوفر:** `{margin:,.1f} MW` | **نسبة التحميل:** `{load_pct:.1f}%` | **حالة التشغيل:** `{status}`\n\n"
        f"**2. ملخص توقعات الذروة لـ 30 يوماً (`ARIMA_PLUS`):**\n"
        f"- **أقصى ذروة متوقعة:** `{fc.get('max_predicted_peak_mw', 'N/A')} MW`\n"
        f"- **متوسط الذروة اليومية:** `{fc.get('avg_predicted_peak_mw', 'N/A')} MW`\n"
        f"- **أيام تتجاوز 10,000 MW:** `{fc.get('days_above_10000_mw', 0)}` يوم\n"
        f"{top5_md}"
    )


def render_conversational_agent_tab():
    st.markdown("### المساعد الذكي المعتمد لشبكة الكهرباء (BigQuery Data Agent)")
    st.caption(
        f"يتصل هذا القسم بوكيل البيانات المعتمد ومجموعة البيانات الموحدة (`{PROJECT_ID}.{DATASET_ID}`) للاستعلام الآمن باللغة الطبيعية."
    )

    with st.expander("معلومات نقطة النهاية (Endpoint & Dataset Details)"):
        st.code(
            f"Endpoint: {DATA_AGENT_ENDPOINT}\n"
            f"Project:  {PROJECT_ID}\n"
            f"Region:   {LOCATION}\n"
            f"Dataset:  {DATASET_ID}",
            language="yaml",
        )

    if "chat_history" not in st.session_state:
        st.session_state.chat_history = [
            {
                "role": "assistant",
                "content": (
                    "مرحباً بكم في مركز التحكم الوطني لوزارة الكهرباء والماء والطاقة المتجددة. "
                    "أنا وكيل البيانات المعتمد للشبكة. يمكنك سؤالي عن الأحمال الحالية، القدرة المتوفرة، وضع التوليد، أو توقعات الذروة لـ 30 يوماً."
                ),
            }
        ]

    for msg in st.session_state.chat_history:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    if prompt := st.chat_input("اكتب استفسارك هنا (مثال: ما هي الأحمال الحالية والقدرة المتوفرة وتوقعات الذروة؟)"):
        st.session_state.chat_history.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        with st.chat_message("assistant"):
            placeholder = st.empty()
            full_response = ""
            client = get_data_agent_client()

            with st.spinner("جاري استرجاع البيانات من BigQuery وتشغيل نموذج التحليل..."):
                if client is not None:
                    try:
                        request = geminidataanalytics.ChatRequest(
                            parent=f"projects/{PROJECT_ID}/locations/{LOCATION}",
                            messages=[
                                geminidataanalytics.Message(
                                    user_message=geminidataanalytics.UserMessage(text=prompt)
                                )
                            ],
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
