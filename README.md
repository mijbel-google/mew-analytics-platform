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
- **Modernized Bilingual Arabic RTL SCADA Control Room Data App (`Streamlit` on `Cloud Run`)**:
  - Neutral high-contrast slate UI with system font stacks, tabular numeric legibility, and color-blindness accessible zone indicators (patterns, border weights, and symbols).
  - **Tab 1 — ⚡ لوحة التحكم اللحظية (SCADA Balance)**: Real-time speedometer dial gauge (`0–100%` capacity zones), accessible 3-zone operating legend (`[✔] التشغيل الآمن`, `[▲] التشغيل الحرج`, `[✖] القطع المبرمج`), and dual national balance equations (`الأحمال الحالية` & `القدرة المتوفرة`).
  - **Tab 2 — 📈 توقعات ذروة الأحمال لـ 30 يوماً (ARIMA+)**: Interactive 30-day peak demand curve with 85% confidence bounds.
  - **Tab 3 — 🧪 محاكاة سيناريوهات الإجهاد الحراري (What-If BQML)**: Live thermal stress simulator invoking `ML.PREDICT` on `load_regression_model`.
  - **Tab 4 — 🤖 وكيل طاقة الكويت (KEI Agent)**: Conversational analytics powered by the BigQuery Data Agent (**Kuwait Energy Intelligence Agent**) restricted strictly to Gold views and tables, with grounded Gemini 2.5 Flash + BigQuery SQL fallback.

---

## 2. Repository Structure

```text
mew-analytics-platform/
├── README.md                                 # Architecture, Script Order & Manual Setup Runbook
├── deploy_mew_solution.sh                    # Master onboarding & end-to-end deployment script
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
│   ├── deploy_composer_env.sh                # Cloud Composer 3 provisioning script
│   ├── sync_dags.sh                          # DAG bucket synchronization & Airflow Variable setter
│   └── deploy_schedulers.sh                  # Wrapper running deploy_composer_env.sh + sync_dags.sh
├── data_app/
│   ├── app.py                                # Streamlit SCADA Control Room & Analytics Hub
│   ├── bigquery_data_agent.py                # KEI BigQuery Data Agent + Gemini SQL fallback
│   ├── assets/
│   │   └── mew_logo.svg                      # Official Kuwait / MEW emblem
│   ├── requirements.txt                      # Python dependencies
│   ├── Dockerfile                            # Production Cloud Run container definition
│   └── deploy_app.sh                         # Artifact Registry + Cloud Build + Cloud Run script
├── data_agent/
│   ├── system_instructions.txt               # Domain guardrails & balance equations for KEI Agent
│   └── golden_queries_catalog.sql            # Verified golden SQL queries (Gold layer only)
├── scripts/
│   └── seed_and_push_github.sh               # GitHub seeding & remote push automation
└── dev_tools/                                # Internal developer validation scripts (Argolis only)
    ├── generate_argolis_synthetic_data.sql   # AI.GENERATE_TABLE synthetic SCADA generator
    └── seed_argolis_bronze.sh                # Argolis bronze seeding script (NOT for customer prod)
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

### B. Deployer / Operator IAM Roles (User or CI Identity Running Scripts)
To provision infrastructure, enable APIs, and bind service account roles, the human operator or CI runner executing the scripts requires **`roles/owner`** or **`roles/editor`** + **`roles/resourcemanager.projectIamAdmin`**, or the following granular roles:
| IAM Role | Purpose |
| :--- | :--- |
| `roles/serviceusage.serviceUsageAdmin` | Enable required GCP APIs on the project |
| `roles/resourcemanager.projectIamAdmin` | Bind IAM roles to pipeline, Cloud Build, Dataform, and IAP service accounts |
| `roles/iam.serviceAccountAdmin` | Create `mew-pipeline-sa` service account |
| `roles/iam.serviceAccountUser` | Attach `mew-pipeline-sa` to Cloud Run and Cloud Composer |
| `roles/bigquery.admin` | Create/manage the unified dataset, tables, views, BQML models, and stored procedures |
| `roles/dataform.admin` | Create and configure Dataform repositories and workflow invocations |
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

*(Note: When deploying a custom BigQuery Conversational Agent, also grant `roles/geminidataanalytics.dataAgentUser` to `mew-pipeline-sa` if cross-principal invocation is required.)*

### D. Dataform & Cloud Build Service Agents
- **Dataform Service Agent (`service-<PROJECT_NUMBER>@gcp-sa-dataform.iam.gserviceaccount.com`)**: Requires **`roles/bigquery.admin`** (to execute SQLX compilations into the unified dataset) and **`roles/secretmanager.secretAccessor`** (if connecting Dataform to a private GitHub repository).
- **Cloud Build / Default Compute Service Account (`<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`)**: Automatically granted `roles/storage.objectAdmin`, `roles/artifactregistry.writer`, `roles/logging.logWriter`, and `roles/cloudbuild.builds.builder`.

### E. End-User Access Roles (Viewing the Cloud Run Data App)
Automatically granted to the active `gcloud` user during deployment:
| IAM Role | Principal | Purpose |
| :--- | :--- | :--- |
| `roles/run.invoker` | End User / Domain & IAP Service Agent (`service-<PROJECT_NUMBER>@gcp-sa-iap.iam.gserviceaccount.com`) | Invoke the `mew-scada-intelligence-hub` Cloud Run service |
| `roles/iap.httpsResourceAccessor` | End User / Domain (e.g., `user:engineer@mew.gov.kw`) | Authenticate through Google Identity-Aware Proxy (IAP) in the browser |

---

## 4. End-to-End Deployment Runbook (Execution Order, Scripts & Manual Steps)

Follow this sequence **in order** from a Linux/macOS/Cloud Shell terminal where `gcloud` and `bq` are installed. First make all shell scripts executable:
```bash
chmod +x deploy_mew_solution.sh \
         orchestration/*.sh \
         data_app/deploy_app.sh \
         scripts/seed_and_push_github.sh \
         dev_tools/seed_argolis_bronze.sh
```

### Quick Execution Order Summary

| Order | Type | Action / Script | Purpose |
| :--- | :--- | :--- | :--- |
| **Step 0** | Manual CLI | `gcloud auth login` & `gcloud config set project` | Authenticate operator session & assign target GCP project |
| **Step 1** | Manual / *Dev Only* | Connect DB Bronze Tables *(or `dev_tools/seed_argolis_bronze.sh`)* | Ensure `POWER_STAT` and `GENERATOR_READINGS` exist in `<DATASET_NAME>` |
| **Step 2** | **Shell Script** | `./deploy_mew_solution.sh` | Master deployment: APIs, IAM, Silver/Gold tables, BQML models, Cloud Run app |
| **Step 3** | **Manual (Console)** | Create & link **Dataform Repository** (Option A) | Required for Cloud Composer DAGs to compile & run Dataform pipelines |
| **Step 4** | **Shell Script** | `./orchestration/deploy_schedulers.sh` | Provision Managed Airflow Gen 3 (`composer-3-airflow-3`) & upload Airflow 3 DAGs |
| **Step 5** | **Manual (Console)** | Create & deploy **BigQuery Conversational Agent (KEI Agent)** | Provision Gold-only BigQuery Data Agent & capture Agent ID |
| **Step 6** | **Shell Script** | `./data_app/deploy_app.sh` *(if Agent ID/UI updated)* | Rebuild & redeploy Streamlit SCADA Data App with updated env vars / UI |

---

### Step 0 (Manual CLI): Authenticate `gcloud` & Set Project
Authenticate both your active CLI session and Application Default Credentials (ADC), and assign your target project (for example `electric-load-demo`):
```bash
gcloud auth login --update-adc
gcloud config set project electric-load-demo
gcloud auth application-default set-quota-project electric-load-demo
```
Verify active account and project:
```bash
gcloud config list
```

---

### Step 1 (Manual — Customer Data Sources): Verify Replicated Bronze Tables
Ensure your database replication pipeline (e.g., Datastream / BigQuery DTS) has landed your two raw tables inside your target unified BigQuery dataset (default: `mew_analytics`):
- **Power Station Telemetry Table** (default: `POWER_STAT`):
  `ID, TS, LOAD_MW, FREQUENCY, TEMPERATURE, HUMIDITY, LOADSHED, GCCInterchange, MAX_SF, MAX_PEAK, STAND_BY, ISR, LUR, GCCSchedule, GenTotal, datastream_metadata`
- **Generator Readings Table** (default: `GENERATOR_READINGS`):
  `PowerStatId, GeneratorId, ReadingTime, PowerMW, VoltageKV, FrequencyHz, Status`

> **Internal Demo / Validation Only (`dev_tools/seed_argolis_bronze.sh`)**:  
> Customer environments should **NOT** run synthetic data generation. If you are validating the platform in an empty sandbox/Argolis project (such as `electric-load-demo`) without live SCADA replication, seed synthetic bronze data first using BigQuery `AI.GENERATE_TABLE`:
> ```bash
> GCP_PROJECT_ID="electric-load-demo" GCP_LOCATION="europe-west4" DATASET_NAME="mew_analytics" \
>   ./dev_tools/seed_argolis_bronze.sh
> ```

---

### Step 2 (Shell Script): Run the Master Deployment Script (`deploy_mew_solution.sh`)
Run the master script in either **Interactive** or **Config-Driven** mode.

#### Option A: Interactive Mode (Recommended for First-Time Customer Onboarding)
```bash
./deploy_mew_solution.sh
```
The script will interactively:
1. Display the **Non-Production Disclaimer** and require confirmation.
2. Prompt for `GCP_PROJECT_ID`, `GCP_LOCATION`, unified `DATASET_NAME`, raw table names (`RAW_POWER_STAT_TABLE`, `RAW_GENERATOR_TABLE`), Composer settings, and Cloud Run service name.
3. Enable all required GCP APIs and configure IAM bindings.
4. Validate your raw tables exist in BigQuery.
5. Update `dataform/workflow_settings.yaml` and idempotently materialize Dimension, Silver, and Gold tables via `dataform/materialize_medallion_tables.sql`.
6. Deploy stored procedures and train initial BQML models (`ARIMA_PLUS` and `BOOSTED_TREE_REGRESSOR`) via `dataform/definitions/gold/bqml_models_and_procedures.sql`.
7. Sync Airflow DAGs if your Composer environment already exists, and invoke `./data_app/deploy_app.sh` to deploy the Cloud Run app.

#### Option B: Non-Interactive / Config-Driven Mode
1. Copy and edit the sample config:
   ```bash
   cp mew-env.sample.conf mew-env.conf
   ```
2. Validate prerequisites with `--dry-run` (no GCP mutations):
   ```bash
   ./deploy_mew_solution.sh --config mew-env.conf --dry-run
   ```
3. Execute the deployment:
   ```bash
   ./deploy_mew_solution.sh --config mew-env.conf
   ```

---

### Step 3 (Manual — Option A via Cloud Console): Create & Connect the Dataform Repository (Least Privilege)

> **Why this manual step is required**:  
> `deploy_mew_solution.sh` parameterizes the local `dataform/workflow_settings.yaml` file and materializes Silver/Gold tables directly via BigQuery SQL (`materialize_medallion_tables.sql`), but it does **not** automatically create the remote Dataform repository resource in GCP. Creating and connecting the repository in the Cloud Console is required so that Managed Airflow (`mew_5min_telemetry_inference_dag`) can trigger `DataformCreateCompilationResultOperator` and `DataformCreateWorkflowInvocationOperator`.
>
> **Note on Managed Airflow vs. Dataform GitHub Access**:  
> Managed Airflow (Cloud Composer 3) does **NOT** need to be connected to GitHub or hold a GitHub token. Airflow reads its DAG Python files from its Cloud Storage DAGs bucket (synced by `sync_dags.sh`), and calls the Dataform API; Dataform itself pulls from GitHub using Secret Manager.

#### 3.1 Create the Dataform Repository in Cloud Console
1. Open the **[Google Cloud Console — BigQuery Dataform](https://console.cloud.google.com/bigquery/dataform?project=electric-load-demo)** page.
2. Ensure your target project (e.g., `electric-load-demo`) is selected in the top bar.
3. Click **+ Create repository**:
   - **Repository ID**: `mew-grid-pipeline` *(must match `DATAFORM_REPO` in `mew-env.conf` / Airflow variable `dataform_repository`)*.
   - **Region**: `europe-west4` *(must match `GCP_LOCATION`)*.
   - Click **Create**.
4. **Grant BigQuery Permissions to the Dataform Service Account**:
   - Inside your new Dataform repository, note the Dataform Service Agent (`service-<PROJECT_NUMBER>@gcp-sa-dataform.iam.gserviceaccount.com`).
   - In **IAM & Admin → IAM**, grant it **`roles/bigquery.admin`** on your project so Dataform can compile and materialize Silver/Gold tables and assertions.

#### 3.2 Create a Least-Privilege GitHub Fine-Grained Personal Access Token (PAT)
Use a **Fine-grained token** scoped to a single repository rather than a Classic PAT:
1. Go to **GitHub → Profile Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.
2. Configure:
   - **Token name**: `gcp-dataform-mew-grid-pipeline`
   - **Expiration**: Bounded (e.g., `90 days`).
   - **Resource owner**: Your GitHub user/organization (e.g., `mijbel-google`).
3. Under **Repository access**, select **Only select repositories** → **`mew-analytics-platform`**.
4. Under **Permissions → Repository permissions**:
   - **Strictest Read-Only** *(if Dataform only compiles & runs from GitHub)*: **Contents** = **Read-only**, **Metadata** = **Read-only**.
   - **Read/Write** *(if you also commit/push from Dataform Workspaces)*: **Contents** = **Read and write**, **Metadata** = **Read-only**.
   - Leave all other permissions as **No access**.
5. Click **Generate token** and copy the `github_pat_...` value.

#### 3.3 Store the Token in Secret Manager (Secret-Level IAM Only)
1. Open **[Google Cloud Console — Security → Secret Manager](https://console.cloud.google.com/security/secret-manager?project=electric-load-demo)** *(enable `secretmanager.googleapis.com` if prompted)*.
2. Click **+ Create Secret**:
   - **Name**: `dataform-github-mew-pat`
   - **Secret value**: Paste your `github_pat_...` token.
   - Click **Create secret**.
3. Grant access **on this specific secret only** (not project-wide):
   - Open `dataform-github-mew-pat` → **Permissions** tab → **+ Grant access**.
   - **New principals**: `service-<PROJECT_NUMBER>@gcp-sa-dataform.iam.gserviceaccount.com`
   - **Role**: **`Secret Manager Secret Accessor`** (`roles/secretmanager.secretAccessor`)
   - Click **Save**.

#### 3.4 Link GitHub in Dataform Console
1. Open your Dataform repository (`mew-grid-pipeline`) → **Settings → Git connection → Connect with HTTPS**.
2. Enter:
   - **Remote Git repository URL**: `https://github.com/mijbel-google/mew-analytics-platform.git` *(or your organization's fork)*.
   - **Default branch name**: `main` *(or a dedicated `dataform` subtree branch where `workflow_settings.yaml` sits at branch root)*.
   - **Secret**: `dataform-github-mew-pat` (latest version).
3. Click **Save** and confirm the connection status shows **Connected**. *(If operating air-gapped without GitHub, click **Create Development Workspace** and upload the contents of `dataform/` directly.)*

---

### Step 4 (Shell Scripts): Provision Managed Airflow Gen 3 (Cloud Composer 3) & Sync DAGs
If Managed Airflow was skipped during Step 2 (`PROVISION_NEW_COMPOSER_ENV="false"`), run the orchestration scripts manually in order (takes ~20–30 minutes to provision a new Managed Airflow Gen 3 environment using `composer-3-airflow-3`):

```bash
# Export environment variables matching your deployment (or source mew-env.conf)
source mew-env.conf
export GCP_PROJECT_ID GCP_LOCATION DATASET_NAME RAW_POWER_STAT_TABLE RAW_GENERATOR_TABLE DATAFORM_REPO PUBSUB_TOPIC COMPOSER_ENV_NAME COMPOSER_IMAGE_VERSION SERVICE_ACCOUNT_NAME

# Option 1: Run the combined wrapper (runs deploy_composer_env.sh then sync_dags.sh)
./orchestration/deploy_schedulers.sh

# Option 2: Run each script individually in order
./orchestration/deploy_composer_env.sh   # Provisions Managed Airflow Gen 3, Pub/Sub topic & env vars
./orchestration/sync_dags.sh             # Uploads Airflow 3 DAGs to GCS & sets Airflow Variables
```
Whenever you update DAG Python files under `orchestration/dags/` later, re-run only `./orchestration/sync_dags.sh`.

---

### Step 5 (Manual — Cloud Console): Create & Deploy the BigQuery Conversational Agent (KEI Agent)
Native BigQuery Data Agents (`geminidataanalytics`) are provisioned in the BigQuery Conversational Analytics / Data Agents Studio and registered in Agent Registry:

1. **Verify Gold Layer Assets Exist** (created in Step 2) inside `<GCP_PROJECT_ID>.<DATASET_NAME>`:
   - `realtime_scada_stream_v`
   - `hourly_load`
   - `daily_load`
   - `forecast_30d`
   - `forecast_explain_30d`
   - `realtime_active_alerts`
2. Open **Google Cloud Console → BigQuery → Conversational Analytics / Data Agents** (for EU multi-region data governance, select location **`eu`**; otherwise match your dataset multi-region).
3. Click **+ Create Agent**:
   - **Agent Name**: `KEI Agent` (*Kuwait Energy Intelligence Agent*).
   - **Data Sources (Strictly Gold Layer Only)**: Select **only** the 6 Gold tables and views listed above. Do **not** attach raw Bronze tables (`POWER_STAT`, `GENERATOR_READINGS`) or Silver staging tables.
   - **System Instructions**: Paste the full contents of [`data_agent/system_instructions.txt`](file:///home/mijbel/Projects/MEW/data_agent/system_instructions.txt), and explicitly note: *"Only query Gold views and tables in `<GCP_PROJECT_ID>.<DATASET_NAME>`."*
   - **Golden Queries / Verified Examples**: Add representative queries from [`data_agent/golden_queries_catalog.sql`](file:///home/mijbel/Projects/MEW/data_agent/golden_queries_catalog.sql).
4. **Publish & Copy the Agent Registry Identifier**:
   - Once created, copy the **Agent ID** (e.g., `agent_af15e9f3-80de-406e-9a7a-27edfa795b3f`) and **Location** (e.g., `eu`) from the Agent Details / Registry URN:
     `urn:agent:projects-<PROJECT_NUMBER>:projects:<PROJECT_NUMBER>:locations:<AGENT_LOCATION>:geminidataanalytics:dataAgents:<AGENT_ID>`
5. **Authorize the App Service Account**:
   Ensure `mew-pipeline-sa@<GCP_PROJECT_ID>.iam.gserviceaccount.com` has `roles/aiplatform.user` and `roles/geminidataanalytics.dataAgentUser` (or `roles/geminidataanalytics.dataAgentStatelessUser`) on the project.

---

### Step 6 (Shell Script): Deploy or Update the Cloud Run Data App (`data_app/deploy_app.sh`)
`deploy_mew_solution.sh` invokes this script automatically at Step 5. Run it standalone whenever you update UI code in `data_app/`, modify agent instructions in `data_agent/`, or connect a new KEI Agent ID:

```bash
export GCP_PROJECT_ID="electric-load-demo"
export GCP_LOCATION="europe-west4"
export DATASET_NAME="mew_analytics"

./data_app/deploy_app.sh
```
If you created your **own** custom BigQuery Conversational Agent in Step 5 (different from the default `electric-load-demo` agent), pass its identifiers to the Cloud Run service after deployment:
```bash
gcloud run services update mew-scada-intelligence-hub \
    --region="${GCP_LOCATION}" \
    --project="${GCP_PROJECT_ID}" \
    --update-env-vars="GCP_PROJECT_NUMBER=<YOUR_PROJECT_NUMBER>,BIGQUERY_DATA_AGENT_ID=<YOUR_AGENT_ID>,BIGQUERY_DATA_AGENT_LOCATION=<YOUR_AGENT_LOCATION>"
```

---

### Optional Maintainer Script: Seed & Push to a New GitHub Repository (`scripts/seed_and_push_github.sh`)
If you are cloning/forking this project to host under your organization's GitHub account:
```bash
GITHUB_USER="your-github-org-or-user" GITHUB_REPO_NAME="mew-analytics-platform" \
  ./scripts/seed_and_push_github.sh
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

### 3. Operating Safety Zones (Accessible Visual Indicators)
- **`[✔]` التشغيل الآمن (Safe Operation)**: $\text{Load} < 85\%$ of Available Capacity *(Solid Border)*
- **`[▲]` التشغيل الحرج (Critical / Unsafe Operation)**: $85\% \le \text{Load} < 95\%$ of Available Capacity *(Dashed Border)*
- **`[✖]` القطع المبرمج (Programmed Load Shedding)**: $\text{Load} \ge 95\%$ or $\text{Load Shed} > 0\text{ MW}$ *(Double Border / Striped Pattern)*
