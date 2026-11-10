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
  - **`ARIMA_PLUS` (`daily_peak_forecast_model`)**: 30-day daily peak demand forecasting with regional holiday effects (`holiday_region = 'EMEA'`) and 85% confidence intervals (`forecast_30d`, `forecast_explain_30d`).
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

## 3. Required GCP APIs & IAM Permissions

All required Google Cloud APIs and service account IAM bindings below are **automatically enabled and configured** by `deploy_mew_solution.sh` and `data_app/deploy_app.sh`.

### A. Required Google Cloud APIs
- `bigquery.googleapis.com` — BigQuery core storage & SQL engine
- `bigqueryconnection.googleapis.com` — BigQuery Cloud Resource Connections (for Vertex AI / Gemini)
- `bigquerystorage.googleapis.com` — High-throughput DataFrame reads for Streamlit
- `dataform.googleapis.com` — Dataform SQLX compilation & ELT workflow execution
- `composer.googleapis.com` — GCP Managed Airflow (Cloud Composer)
- `pubsub.googleapis.com` — Real-time grid stress alerting topic (`grid-stress-alerts`)
- `run.googleapis.com` — Cloud Run serverless container hosting
- `cloudbuild.googleapis.com` — Cloud Build container image packaging
- `artifactregistry.googleapis.com` — Docker image repository (`mew-data-apps`)
- `aiplatform.googleapis.com` — Vertex AI / Gemini foundation models
- `geminidataanalytics.googleapis.com` — Conversational BigQuery Data Agent API
- `iap.googleapis.com` — Identity-Aware Proxy for zero-trust browser authentication
- `iam.googleapis.com` — Service account and IAM policy management

### B. Deployer / Operator IAM Roles (User or CI Identity Running `deploy_mew_solution.sh`)
To provision infrastructure, enable APIs, and bind service account roles, the human operator or CI runner executing `deploy_mew_solution.sh` requires **`roles/owner`** or **`roles/editor`** + **`roles/resourcemanager.projectIamAdmin`**, or the following granular roles:
| IAM Role | Purpose |
| :--- | :--- |
| `roles/serviceusage.serviceUsageAdmin` | Enable required GCP APIs on the project |
| `roles/resourcemanager.projectIamAdmin` | Bind IAM roles to pipeline, Cloud Build, and IAP service accounts |
| `roles/iam.serviceAccountAdmin` | Create `mew-pipeline-sa` service account |
| `roles/iam.serviceAccountUser` | Attach `mew-pipeline-sa` to Cloud Run and Cloud Composer |
| `roles/bigquery.admin` | Create/manage the unified dataset, tables, views, BQML models, and stored procedures |
| `roles/dataform.admin` | Configure Dataform repositories and workflow invocations |
| `roles/composer.admin` | Provision/update Cloud Composer environments and upload Airflow DAGs |
| `roles/pubsub.admin` | Create and manage the `grid-stress-alerts` Pub/Sub topic |
| `roles/artifactregistry.admin` | Create the `mew-data-apps` Docker repository |
| `roles/cloudbuild.builds.editor` | Submit container builds via `gcloud builds submit` |
| `roles/run.admin` | Deploy and configure the `mew-scada-intelligence-hub` Cloud Run service |
| `roles/iap.admin` | Enable Identity-Aware Proxy (IAP) on Cloud Run and grant user access |

### C. Pipeline & Data App Service Account (`mew-pipeline-sa@<PROJECT_ID>.iam.gserviceaccount.com`)
Automatically created and granted by `deploy_mew_solution.sh`:
| IAM Role | Purpose |
| :--- | :--- |
| `roles/bigquery.dataEditor` | Read/write Silver & Gold tables, forecast archives, and alert tables |
| `roles/bigquery.jobUser` | Execute BigQuery SQL queries, stored procedures, and `ML.PREDICT` jobs |
| `roles/bigquery.readSessionUser` | Accelerated BigQuery Storage API reads in the Streamlit Data App |
| `roles/dataform.editor` | Compile and invoke Dataform SQLX pipelines from Managed Airflow |
| `roles/pubsub.publisher` | Publish critical grid stress alerts to Cloud Pub/Sub |
| `roles/aiplatform.user` | Invoke Gemini models and the BigQuery Data Agent (`geminidataanalytics`) |
| `roles/composer.worker` | Execute Managed Airflow worker tasks in Cloud Composer |

### D. Cloud Build / Default Compute Service Account (`<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`)
Automatically bound by `deploy_mew_solution.sh` and `data_app/deploy_app.sh`:
| IAM Role | Purpose |
| :--- | :--- |
| `roles/storage.objectAdmin` | Read/stage source archives in the `gs://<PROJECT_ID>_cloudbuild` bucket |
| `roles/artifactregistry.writer` | Push built Docker container images to Artifact Registry |
| `roles/logging.logWriter` | Stream container build logs to Cloud Logging |
| `roles/cloudbuild.builds.builder` | Execute Cloud Build steps |

### E. End-User Access Roles (Viewing the Cloud Run Data App)
Automatically granted to the active `gcloud` user during deployment:
| IAM Role | Principal | Purpose |
| :--- | :--- | :--- |
| `roles/run.invoker` | End User / Domain & IAP Service Agent (`service-<PROJECT_NUMBER>@gcp-sa-iap.iam.gserviceaccount.com`) | Invoke the `mew-scada-intelligence-hub` Cloud Run service |
| `roles/iap.httpsResourceAccessor` | End User / Domain (e.g., `user:engineer@mew.gov.kw`) | Authenticate through Google Identity-Aware Proxy (IAP) in the browser |

---

## 4. Customer Deployment Guide (MEW Engineers)

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
3. Enable all required GCP APIs and configure IAM roles for the service accounts and active operator.
4. Verify your raw tables exist in BigQuery.
5. Idempotently create the Silver and Gold tables, views, BQML models (`ARIMA_PLUS` and `BOOSTED_TREE_REGRESSOR`), and stored procedures in the same dataset.
6. Synchronize the Airflow DAGs to your Cloud Composer environment.
7. Build and deploy the Streamlit SCADA Control Room Data App to Cloud Run with Identity-Aware Proxy (IAP).

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

## 5. Securely Accessing the SCADA Control Room Data App

In enterprise Google Cloud organizations (including Argolis), the **Domain Restricted Sharing** policy (`constraints/iam.allowedPolicyMemberDomains`) prevents public unauthenticated (`allUsers`) access to Cloud Run services. Calling the `.run.app` URL without authentication returns `403: Forbidden`.

You can securely access the deployed application using either of the two methods below:

### Method 1: Direct Browser Sign-In via Identity-Aware Proxy (IAP)
The deployment script enables **Cloud Run Native IAP (`--iap`)** and grants `roles/iap.httpsResourceAccessor` and `roles/run.invoker` to the deployer account:
1. Open the Cloud Run URL directly in your browser:
   `https://mew-scada-intelligence-hub-928308690350.europe-west4.run.app`
2. Sign in with your authorized Google Cloud / Workspace account (e.g., `admin@mijbel.altostrat.com`).
3. To authorize additional MEW engineers for browser access:
   ```bash
   gcloud projects add-iam-policy-binding <GCP_PROJECT_ID> \
       --member="user:engineer@domain.com" \
       --role="roles/iap.httpsResourceAccessor"
   gcloud run services add-iam-policy-binding mew-scada-intelligence-hub \
       --region=<GCP_LOCATION> \
       --project=<GCP_PROJECT_ID> \
       --member="user:engineer@domain.com" \
       --role="roles/run.invoker"
   ```

### Method 2: Local Authenticated Tunnel via `gcloud run services proxy`
If you prefer to connect from your workstation without browser IAP cookies, use the built-in `gcloud` authenticated proxy, which automatically attaches your OIDC Bearer token to every request:
```bash
gcloud run services proxy mew-scada-intelligence-hub \
    --project=electric-load-demo \
    --region=europe-west4 \
    --port=8080
```
Then open **`http://localhost:8080`** in your browser.

---

## 6. National Grid Balance Equations Implemented in Gold & Data App

### 1. Current Load Balance (`الأحمال الحالية`)
$$\text{الأحمال الحالية (Current Load)} = \text{إجمالي الإنتاج الحالي (Net Generation)} + \text{تبادل الطاقة الحالي مع الربط الخليجي (GCC Exchange)} + \text{الأحمال المفصوله (Load Shed)}$$

### 2. Available Capacity Balance (`القدرة المتوفرة`)
$$\text{القدرة المتوفرة (Available Capacity)} = \text{الإنتاج الكلي (Gross Production)} + \text{الطاقة الإحتياطية المتوفرة (Available Reserve)} + \text{الطاقة المزودة من الربط الخليجي (GCC Supplied)} - \text{الإحتياطي المطلوب الإلتزام به مع الربط الخليجي (GCC Obligation)}$$

### 3. Operating Safety Zones
- 🟩 **التشغيل الآمن (Safe Operation)**: $\text{Load} < 85\%$ of Available Capacity
- 🟧 **التشغيل الغير آمن (Unsafe Operation)**: $85\% \le \text{Load} < 95\%$ of Available Capacity
- 🟥 **القطع المبرمج (Programmed Load Shedding)**: $\text{Load} \ge 95\%$ or $\text{Load Shed} > 0\text{ MW}$
