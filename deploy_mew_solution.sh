#!/usr/bin/env bash
# =============================================================================
# Ministry of Electricity & Water and Renewable Energy (MEW) - State of Kuwait
# Energy Intelligence Platform - Customer Onboarding & Deployment Script
#
# Supports:
#   1. Interactive Mode:     ./deploy_mew_solution.sh
#   2. Non-Interactive Mode: ./deploy_mew_solution.sh --config mew-env.conf
# =============================================================================
set -euo pipefail

# Clean certificate environment variables for BigQuery CLI compatibility
unset CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE GOOGLE_API_CERTIFICATE_CONFIG CLOUDSDK_CONTEXT_AWARE_CERTIFICATE_CONFIG_FILE_PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
ACCEPT_NON_PROD_DISCLAIMER="${ACCEPT_NON_PROD_DISCLAIMER:-false}"
DRY_RUN="false"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --config <path>         Path to configuration file (e.g., mew-env.sample.conf)
  --accept-disclaimer     Acknowledge the non-production environment disclaimer
  --dry-run               Validate prerequisites and configuration without mutating GCP resources
  -h, --help              Display this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --accept-disclaimer)
            ACCEPT_NON_PROD_DISCLAIMER="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

# =============================================================================
# 1. NON-PRODUCTION ENVIRONMENT DISCLAIMER
# =============================================================================
cat <<'EOF'
================================================================================
⚠️  DISCLAIMER: NON-PRODUCTION DEPLOYMENT ONLY
--------------------------------------------------------------------------------
This Data Analytics & AI sample solution for the Ministry of Electricity and
Water and Renewable Energy (MEW) is provided strictly for TESTING, STAGING,
VALIDATION, and NON-PRODUCTION environments only.

Do NOT deploy this sample directly into production SCADA control networks or
mission-critical grid operational environments without formal security review,
change management approval, and production hardening.
================================================================================
EOF

if [[ -n "${CONFIG_FILE}" ]]; then
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "ERROR: Configuration file '${CONFIG_FILE}' not found." >&2
        exit 1
    fi
    echo "==> Loading configuration from '${CONFIG_FILE}'..."
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
fi

if [[ "${ACCEPT_NON_PROD_DISCLAIMER}" != "true" ]]; then
    read -r -p "Do you confirm that the target environment is a NON-PRODUCTION environment? (yes/no): " CONFIRM_DISCLAIMER
    if [[ ! "${CONFIRM_DISCLAIMER}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Deployment aborted. You must confirm non-production usage to proceed."
        exit 1
    fi
fi

# =============================================================================
# 2. INTERACTIVE PROMPTS (WHEN NO CONFIG FILE IS SUPPLIED)
# =============================================================================
if [[ -z "${CONFIG_FILE}" ]]; then
    echo ""
    echo "==> Please enter your GCP & BigQuery environment parameters:"
    read -r -p "1. GCP Project ID [electric-load-demo]: " INPUT_PROJECT
    GCP_PROJECT_ID="${INPUT_PROJECT:-electric-load-demo}"

    read -r -p "2. GCP Region [europe-west4]: " INPUT_REGION
    GCP_LOCATION="${INPUT_REGION:-europe-west4}"

    read -r -p "3. Unified BigQuery Dataset Name (all tables reside here) [mew_analytics]: " INPUT_DATASET
    DATASET_NAME="${INPUT_DATASET:-mew_analytics}"

    read -r -p "4. Existing Raw Power Stat Table Name in '${DATASET_NAME}' [POWER_STAT]: " INPUT_RAW_PS
    RAW_POWER_STAT_TABLE="${INPUT_RAW_PS:-POWER_STAT}"

    read -r -p "5. Existing Raw Generator Readings Table Name in '${DATASET_NAME}' [GENERATOR_READINGS]: " INPUT_RAW_GR
    RAW_GENERATOR_TABLE="${INPUT_RAW_GR:-GENERATOR_READINGS}"

    read -r -p "6. Deploy/Sync DAGs to GCP Managed Airflow (Cloud Composer)? (true/false) [true]: " INPUT_DEPLOY_COMP
    DEPLOY_COMPOSER="${INPUT_DEPLOY_COMP:-true}"

    if [[ "${DEPLOY_COMPOSER}" == "true" ]]; then
        read -r -p "   Cloud Composer Environment Name [mew-airflow-env]: " INPUT_COMP_ENV
        COMPOSER_ENV_NAME="${INPUT_COMP_ENV:-mew-airflow-env}"
        read -r -p "   Provision new Composer environment if it does not exist? (true/false) [false]: " INPUT_PROV_COMP
        PROVISION_NEW_COMPOSER_ENV="${INPUT_PROV_COMP:-false}"
    fi

    read -r -p "7. Deploy Streamlit SCADA Data App to Cloud Run? (true/false) [true]: " INPUT_DEPLOY_APP
    DEPLOY_DATA_APP="${INPUT_DEPLOY_APP:-true}"

    if [[ "${DEPLOY_DATA_APP}" == "true" ]]; then
        read -r -p "   Cloud Run Service Name [mew-scada-intelligence-hub]: " INPUT_SVC_NAME
        SERVICE_NAME="${INPUT_SVC_NAME:-mew-scada-intelligence-hub}"
    fi
fi

# Apply defaults for any unset variables
export GCP_PROJECT_ID="${GCP_PROJECT_ID:-electric-load-demo}"
export GCP_LOCATION="${GCP_LOCATION:-europe-west4}"
export DATASET_NAME="${DATASET_NAME:-mew_analytics}"
export RAW_POWER_STAT_TABLE="${RAW_POWER_STAT_TABLE:-POWER_STAT}"
export RAW_GENERATOR_TABLE="${RAW_GENERATOR_TABLE:-GENERATOR_READINGS}"
export DATAFORM_REPO="${DATAFORM_REPO:-mew-grid-pipeline}"
export PUBSUB_TOPIC="${PUBSUB_TOPIC:-grid-stress-alerts}"
export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-mew-pipeline-sa}"
export DEPLOY_COMPOSER="${DEPLOY_COMPOSER:-true}"
export PROVISION_NEW_COMPOSER_ENV="${PROVISION_NEW_COMPOSER_ENV:-false}"
export COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:-mew-airflow-env}"
export DEPLOY_DATA_APP="${DEPLOY_DATA_APP:-true}"
export SERVICE_NAME="${SERVICE_NAME:-mew-scada-intelligence-hub}"
export REPO_NAME="${REPO_NAME:-mew-data-apps}"

cat <<EOF

================================================================================
📋 DEPLOYMENT SUMMARY
--------------------------------------------------------------------------------
  GCP Project ID           : ${GCP_PROJECT_ID}
  GCP Region               : ${GCP_LOCATION}
  Unified BigQuery Dataset : ${GCP_PROJECT_ID}:${DATASET_NAME}
  Raw Power Stat Table     : ${GCP_PROJECT_ID}:${DATASET_NAME}.${RAW_POWER_STAT_TABLE}
  Raw Generator Table      : ${GCP_PROJECT_ID}:${DATASET_NAME}.${RAW_GENERATOR_TABLE}
  Deploy Managed Airflow   : ${DEPLOY_COMPOSER} (${COMPOSER_ENV_NAME})
  Deploy Cloud Run App     : ${DEPLOY_DATA_APP} (${SERVICE_NAME})
  Dry-Run Mode             : ${DRY_RUN}
================================================================================
EOF

# =============================================================================
# 3. PREREQUISITE & CLI VERIFICATION
# =============================================================================
for BIN in gcloud bq sed; do
    if ! command -v "${BIN}" >/dev/null 2>&1; then
        echo "ERROR: Required CLI tool '${BIN}' is not installed or not in PATH." >&2
        exit 1
    fi
done

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "==> [Dry-Run] Configuration and CLI prerequisites verified successfully."
    exit 0
fi

# =============================================================================
# 4. API ENABLEMENT, IAM PERMISSIONS & DATASET VERIFICATION
# =============================================================================
echo "==> [Step 1/5] Enabling required Google Cloud APIs & IAM permissions in '${GCP_PROJECT_ID}'..."
gcloud services enable \
    bigquery.googleapis.com \
    bigqueryconnection.googleapis.com \
    bigquerystorage.googleapis.com \
    dataform.googleapis.com \
    pubsub.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    aiplatform.googleapis.com \
    geminidataanalytics.googleapis.com \
    iap.googleapis.com \
    iam.googleapis.com \
    --project="${GCP_PROJECT_ID}" \
    --quiet

if [[ "${DEPLOY_COMPOSER}" == "true" && "${PROVISION_NEW_COMPOSER_ENV}" == "true" ]]; then
    gcloud services enable composer.googleapis.com --project="${GCP_PROJECT_ID}" --quiet
fi

SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
echo "==> Ensuring Pipeline & Data App Service Account (${SERVICE_ACCOUNT}) and IAM roles..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" --project="${GCP_PROJECT_ID}" --quiet >/dev/null 2>&1; then
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="MEW Energy Analytics Pipeline & App Service Account" \
        --project="${GCP_PROJECT_ID}" \
        --quiet
fi

for SA_ROLE in \
    "roles/bigquery.dataEditor" \
    "roles/bigquery.jobUser" \
    "roles/bigquery.readSessionUser" \
    "roles/dataform.editor" \
    "roles/pubsub.publisher" \
    "roles/aiplatform.user" \
    "roles/composer.worker"; do
    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT}" \
        --role="${SA_ROLE}" \
        --condition=None \
        --quiet >/dev/null || true
done

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "==> Ensuring Cloud Build / Compute Service Account (${COMPUTE_SA}) build permissions..."
for CB_ROLE in \
    "roles/storage.objectAdmin" \
    "roles/artifactregistry.writer" \
    "roles/logging.logWriter" \
    "roles/cloudbuild.builds.builder"; do
    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
        --member="serviceAccount:${COMPUTE_SA}" \
        --role="${CB_ROLE}" \
        --condition=None \
        --quiet >/dev/null || true
done

ACTIVE_USER="$(gcloud config get-value account 2>/dev/null || true)"
if [[ -n "${ACTIVE_USER}" ]]; then
    echo "==> Granting Cloud Run Invoker & IAP Accessor roles to active operator (${ACTIVE_USER})..."
    for USER_ROLE in "roles/run.invoker" "roles/iap.httpsResourceAccessor"; do
        gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
            --member="user:${ACTIVE_USER}" \
            --role="${USER_ROLE}" \
            --condition=None \
            --quiet >/dev/null || true
    done
fi

echo "==> Ensuring Unified BigQuery Dataset '${GCP_PROJECT_ID}:${DATASET_NAME}' exists..."
if ! bq show --project_id="${GCP_PROJECT_ID}" "${GCP_PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
    bq --location="${GCP_LOCATION}" mk --dataset \
        --label datacloud:antigravity \
        --description="MEW Unified Energy Intelligence Dataset (Bronze, Silver, Gold & BQML)" \
        "${GCP_PROJECT_ID}:${DATASET_NAME}"
fi

echo "==> Checking customer connected raw tables in '${GCP_PROJECT_ID}:${DATASET_NAME}'..."
for RAW_TBL in "${RAW_POWER_STAT_TABLE}" "${RAW_GENERATOR_TABLE}"; do
    if ! bq show --project_id="${GCP_PROJECT_ID}" "${GCP_PROJECT_ID}:${DATASET_NAME}.${RAW_TBL}" >/dev/null 2>&1; then
        echo "ERROR: Expected customer raw table '${GCP_PROJECT_ID}:${DATASET_NAME}.${RAW_TBL}' was not found." >&2
        echo "       Please verify that your database replication into BigQuery has created '${RAW_TBL}' in dataset '${DATASET_NAME}'." >&2
        exit 1
    fi
    echo "    Found raw source table: ${GCP_PROJECT_ID}:${DATASET_NAME}.${RAW_TBL}"
done

# =============================================================================
# 5. UPDATE DATAFORM CONFIGURATION & MATERIALIZE SILVER/GOLD TABLES
# =============================================================================
echo "==> [Step 2/5] Updating Dataform workflow_settings.yaml for unified dataset '${DATASET_NAME}'..."
cat > "${SCRIPT_DIR}/dataform/workflow_settings.yaml" <<EOF
defaultProject: "${GCP_PROJECT_ID}"
defaultLocation: "${GCP_LOCATION}"
defaultDataset: "${DATASET_NAME}"
assertionDataset: "${DATASET_NAME}"
dataformCoreVersion: "3.0.0"

vars:
  targetDataset: "${DATASET_NAME}"
  rawPowerStatTable: "${RAW_POWER_STAT_TABLE}"
  rawGeneratorTable: "${RAW_GENERATOR_TABLE}"
  timezone: "Asia/Kuwait"
  maxLoadThresholdMw: "25000"
  minTempThresholdC: "-10.0"
  maxTempThresholdC: "70.0"
  minFrequencyHz: "35.0"
  maxFrequencyHz: "65.0"
  criticalLoadAlertMw: "12000"
EOF

echo "==> Materializing Dimension, Silver, and Gold tables idempotently in '${GCP_PROJECT_ID}:${DATASET_NAME}'..."
sed -e "s/__PROJECT_ID__/${GCP_PROJECT_ID}/g" \
    -e "s/__DATASET_NAME__/${DATASET_NAME}/g" \
    -e "s/__RAW_POWER_STAT_TABLE__/${RAW_POWER_STAT_TABLE}/g" \
    -e "s/__RAW_GENERATOR_TABLE__/${RAW_GENERATOR_TABLE}/g" \
    "${SCRIPT_DIR}/dataform/materialize_medallion_tables.sql" | \
    bq query \
        --project_id="${GCP_PROJECT_ID}" \
        --location="${GCP_LOCATION}" \
        --use_legacy_sql=false \
        --label datacloud:antigravity

# =============================================================================
# 6. DEPLOY BQML MODELS & STORED PROCEDURES
# =============================================================================
echo "==> [Step 3/5] Deploying BQML Stored Procedures & training initial Forecast/Regression models..."
sed -e "s/electric-load-demo/${GCP_PROJECT_ID}/g" \
    -e "s/mew_analytics/${DATASET_NAME}/g" \
    "${SCRIPT_DIR}/dataform/definitions/gold/bqml_models_and_procedures.sql" | \
    bq query \
        --project_id="${GCP_PROJECT_ID}" \
        --location="${GCP_LOCATION}" \
        --use_legacy_sql=false \
        --label datacloud:antigravity

echo "==> Executing initial model training & 30-day forecast archival procedure..."
bq query \
    --project_id="${GCP_PROJECT_ID}" \
    --location="${GCP_LOCATION}" \
    --use_legacy_sql=false \
    --label datacloud:antigravity \
    "CALL \`${GCP_PROJECT_ID}.${DATASET_NAME}.sp_daily_model_retrain_and_archive\`();"

echo "==> Executing initial 5-minute real-time inference & alert scoring procedure..."
bq query \
    --project_id="${GCP_PROJECT_ID}" \
    --location="${GCP_LOCATION}" \
    --use_legacy_sql=false \
    --label datacloud:antigravity \
    "CALL \`${GCP_PROJECT_ID}.${DATASET_NAME}.sp_run_realtime_inference_and_alerts\`();"

# =============================================================================
# 7. ORCHESTRATION ON GCP MANAGED AIRFLOW (CLOUD COMPOSER)
# =============================================================================
echo "==> [Step 4/5] Configuring GCP Managed Airflow (Cloud Composer) Orchestration..."
if [[ "${DEPLOY_COMPOSER}" == "true" ]]; then
    if [[ "${PROVISION_NEW_COMPOSER_ENV}" == "true" ]]; then
        bash "${SCRIPT_DIR}/orchestration/deploy_composer_env.sh"
    fi
    if gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
        --location="${GCP_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        --quiet >/dev/null 2>&1; then
        bash "${SCRIPT_DIR}/orchestration/sync_dags.sh"
    else
        echo "    Note: Cloud Composer environment '${COMPOSER_ENV_NAME}' not yet provisioned in '${GCP_LOCATION}'."
        echo "          Run 'PROVISION_NEW_COMPOSER_ENV=true ./orchestration/deploy_composer_env.sh' when ready."
    fi
else
    echo "    Skipping Cloud Composer deployment (DEPLOY_COMPOSER=${DEPLOY_COMPOSER})."
fi

# =============================================================================
# 8. STREAMLIT DATA APP DEPLOYMENT ON CLOUD RUN
# =============================================================================
echo "==> [Step 5/5] Deploying MEW Energy Intelligence Data App to Cloud Run..."
if [[ "${DEPLOY_DATA_APP}" == "true" ]]; then
    bash "${SCRIPT_DIR}/data_app/deploy_app.sh"
else
    echo "    Skipping Cloud Run Data App deployment (DEPLOY_DATA_APP=${DEPLOY_DATA_APP})."
fi

echo ""
echo "================================================================================"
echo "✅ MEW ENERGY INTELLIGENCE PLATFORM DEPLOYMENT COMPLETE!"
echo "   Project  : ${GCP_PROJECT_ID}"
echo "   Dataset  : ${GCP_PROJECT_ID}:${DATASET_NAME}"
echo "================================================================================"
