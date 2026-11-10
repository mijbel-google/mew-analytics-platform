# ⚡ MEW Kuwait — Energy Intelligence & SCADA Analytics Platform

**وزارة الكهرباء والماء والطاقة المتجددة — دولة الكويت**  
**Ministry of Electricity & Water & Renewable Energy (MEW) — State of Kuwait**

> ⚠️ **NON-PRODUCTION DISCLAIMER**  
> This repository and its automated deployment scripts are engineered strictly for **NON-PRODUCTION, STAGING, DEMO, and VALIDATION** environments. Do **NOT** connect or deploy this sample directly into mission-critical operational SCADA control networks without formal security review and production hardening.

---

## 1. Executive Overview

The **MEW Energy Intelligence Platform** is an end-to-end Google Cloud Data Analytics & AI solution designed for national electrical grid load monitoring, 30-day peak demand forecasting, thermal stress simulation, and conversational grid intelligence.

### Key Capabilities
- **Unified Single-Dataset Medallion Architecture (`Dataform` + `BigQuery`)**:
  - Connects directly to the customer's existing replicated raw/bronze tables (e.g., `POWER_STAT` and `GENERATOR_READINGS`) in a single unified BigQuery dataset.
  - Materializes curated Silver (`load_telemetry_silver`) and Gold (`realtime_scada_stream_v`, `hourly_load`, `daily_load`) tables and views with strict operational range assertions and complete idempotency.
- **Machine Learning & Peak Forecasting (`BigQuery ML`)**:
  - **`ARIMA_PLUS` (`daily_peak_forecast_model`)**: 30-day daily peak demand forecasting with Kuwait holiday effects (`holiday_region = 'KW'`) and 85% confidence intervals (`forecast_30d`, `forecast_explain_30d`).
  - **`BOOSTED_TREE_REGRESSOR` (`load_regression_model`)**: Non-linear thermal sensitivity model for 5-minute anomaly detection (`realtime_predictions_5min`, `realtime_active_alerts`) and interactive What-If heat-wave simulation.
- **Managed Workflow Orchestration (`GCP Managed Airflow / Cloud Composer`)**:
  - **`mew_5min_telemetry_inference_dag`**: Runs every 5 minutes to trigger incremental Dataform transformations, execute real-time BQML anomaly detection, and publish grid stress alerts to Cloud Pub/Sub.
  - **`mew_daily_retrain_forecast_dag`**: Runs daily at 01:00 AM Kuwait time (`22:00 UTC`) to retrain BQML models and archive 30-day forecast trajectories.
- **Bilingual Arabic RTL SCADA Control Room Data App (`Streamlit` on `Cloud Run`)**:
  - **Tab 1 — ⚡ لوحة التحكم اللحظية (SCADA Balance)**: Real-time analog speedometer dial gauge (`0–100%` capacity zones), 3-zone operating legend (`التشغيل الآمن`, `التشغيل الغير آمن`, `القطع المبرمج`), and dual national balance equations (`الأحمال الحالية` & `القدرة المتوفرة`).
  - **Tab 2 — 📈 توقعات ذروة الأحمال لـ 30 يوماً (ARIMA+)**: Interactive 30-day peak demand curve with 85% confidence bounds.
  - **Tab 3 — 🧪 محاكاة سيناريوهات الإجهاد الحراري (What-If BQML)**: Live thermal stress simulator invoking `ML.PREDICT` on `load_regression_model`.
  - **Tab 4 — 🤖 المساعد الذكي المعتمد (BigQuery Data Agent)**: Natural language conversational analytics powered by the BigQuery Data Agent API (`geminidataanalytics`) with automatic Gemini + BigQuery SQL fallback.

---

## 2. Repository Structure

```text
mew-analytics-platform/
├── README.md                                 # Comprehensive Architecture & Deployment Guide
├── deploy_mew_solution.sh                    # Dual-mode customer onboarding & deployment script
├── mew-env.sample.conf                       # Sample configuration file for non-interactive deployment
├── dataform/
│   ├── workflow_settings.yaml                # Unified dataset & variable configuration
│   ├── materialize_medallion_tables.sql      # Idempotent SQL materialization for Silver & Gold
│   ├── includes/
│   │   └── constants.js                      # Unified dataset & operational thresholds
│   └── definitions/
│       ├── sources/
│       │   └── raw_sources.js                # Dynamic customer raw table declarations
│       ├── dimensions/
│       │   ├── calendar_reference.sqlx       # Kuwait holidays & seasonal calendar (2020-2035)
│       │   └── calendar_reference.sql
│       ├── silver/
│       │   ├── load_telemetry_silver.sqlx    # Deduplicated SCADA + generator rollup + calendar join
│       │   └── assert_telemetry_ranges.sqlx  # Operational quality assertions
│       └── gold/
│           ├── realtime_scada_stream_v.sqlx  # Live SCADA balance & safety margin view
│           ├── hourly_load.sqlx              # Hourly aggregations & 24h lag features
│           ├── daily_load.sqlx               # Daily peak demand & 7d autoregressive features
│           └── bqml_models_and_procedures.sql# BQML models & stored procedures
├── orchestration/
│   ├── dags/
│   │   ├── mew_5min_telemetry_inference_dag.py # 5-min Dataform + BQML inference + Pub/Sub DAG
│   │   └── mew_daily_retrain_forecast_dag.py   # Daily BQML retraining & forecast archival DAG
│   ├── deploy_composer_env.sh                # Cloud Composer 2/3 provisioning script
│   ├── sync_dags.sh                          # DAG bucket synchronization & Airflow Variable setter
│   └── deploy_schedulers.sh                  # Orchestration deployment wrapper
├── data_app/
│   ├── app.py                                # Streamlit SCADA Control Room & Analytics Hub
│   ├── bigquery_data_agent.py                # BigQuery Data Agent + Gemini SQL fallback
│   ├── assets/
│   │   └── mew_logo.svg                      # Official Kuwait / MEW emblem
│   ├── requirements.txt                      # Python dependencies
│   ├── Dockerfile                            # Production Cloud Run container definition
│   └── deploy_app.sh                         # Artifact Registry + Cloud Build + Cloud Run script
├── data_agent/
│   ├── system_instructions.txt               # Domain guardrails & balance equations for Data Agent
│   └── golden_queries_catalog.sql            # Verified golden SQL queries
├── scripts/
│   └── seed_and_push_github.sh               # GitHub seeding & remote push automation
└── dev_tools/                                # Internal developer validation scripts (Argolis only)
    ├── generate_argolis_synthetic_data.sql   # AI.GENERATE_TABLE synthetic SCADA generator
    └── seed_argolis_bronze.sh                # Argolis bronze seeding script
```

---

## 3. Customer Deployment Guide (MEW Engineers)

### Prerequisites
1. **Google Cloud SDK (`gcloud`)** and **BigQuery CLI (`bq`)** installed and authenticated:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
2. **Existing Connected Raw Tables in BigQuery**:
   Ensure your database replication (e.g., Datastream / DTS) has landed your two raw tables inside your target BigQuery dataset:
   - **Power Station Telemetry Table** (default: `POWER_STAT`):
     `ID, TS, LOAD_MW, FREQUENCY, TEMPERATURE, HUMIDITY, LOADSHED, GCCInterchange, MAX_SF, MAX_PEAK, STAND_BY, ISR, LUR, GCCSchedule, GenTotal, datastream_metadata`
   - **Generator Readings Table** (default: `GENERATOR_READINGS`):
     `PowerStatId, GeneratorId, ReadingTime, PowerMW, VoltageKV, FrequencyHz, Status`

### Option A: Interactive Deployment (Recommended for First-Time Run)
Run the customer deployment script and follow the interactive prompts:
```bash
chmod +x deploy_mew_solution.sh
./deploy_mew_solution.sh
```
The script will:
1. Display the **Non-Production Disclaimer** and ask for confirmation.
2. Prompt for your `GCP_PROJECT_ID`, `GCP_LOCATION`, unified `DATASET_NAME`, and the exact names of your raw tables (`RAW_POWER_STAT_TABLE`, `RAW_GENERATOR_TABLE`).
3. Verify your raw tables exist in BigQuery.
4. Idempotently create the Silver and Gold tables, views, BQML models (`ARIMA_PLUS` and `BOOSTED_TREE_REGRESSOR`), and stored procedures in the same dataset.
5. Synchronize the Airflow DAGs to your Cloud Composer environment.
6. Build and deploy the Streamlit SCADA Control Room Data App to Cloud Run.

### Option B: Non-Interactive / Config-Driven Deployment
1. Copy and edit `mew-env.sample.conf`:
   ```bash
   cp mew-env.sample.conf mew-env.conf
   ```
2. Execute the deployment script with `--config`:
   ```bash
   ./deploy_mew_solution.sh --config mew-env.conf
   ```

---

## 4. National Grid Balance Equations Implemented in Gold & Data App

### 1. Current Load Balance (`الأحمال الحالية`)
$$\text{الأحمال الحالية (Current Load)} = \text{إجمالي الإنتاج الحالي (Net Generation)} + \text{تبادل الطاقة الحالي مع الربط الخليجي (GCC Exchange)} + \text{الأحمال المفصوله (Load Shed)}$$

### 2. Available Capacity Balance (`القدرة المتوفرة`)
$$\text{القدرة المتوفرة (Available Capacity)} = \text{الإنتاج الكلي (Gross Production)} + \text{الطاقة الإحتياطية المتوفرة (Available Reserve)} + \text{الطاقة المزودة من الربط الخليجي (GCC Supplied)} - \text{الإحتياطي المطلوب الإلتزام به مع الربط الخليجي (GCC Obligation)}$$

### 3. Operating Safety Zones
- 🟩 **التشغيل الآمن (Safe Operation)**: $\text{Load} < 85\%$ of Available Capacity
- 🟧 **التشغيل الغير آمن (Unsafe Operation)**: $85\% \le \text{Load} < 95\%$ of Available Capacity
- 🟥 **القطع المبرمج (Programmed Load Shedding)**: $\text{Load} \ge 95\%$ or $\text{Load Shed} > 0\text{ MW}$
