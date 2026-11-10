#!/usr/bin/env bash
# =============================================================================
# MEW Energy Intelligence Platform - Managed Airflow DAG Synchronizer
# Idempotently uploads Airflow DAGs to the Cloud Composer GCS bucket
# =============================================================================
set -euo pipefail

# Clean certificate environment variables for BigQuery CLI compatibility
unset CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE GOOGLE_API_CERTIFICATE_CONFIG CLOUDSDK_CONTEXT_AWARE_CERTIFICATE_CONFIG_FILE_PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-electric-load-demo}"
REGION="${GCP_LOCATION:-europe-west4}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:-mew-airflow-env}"
DATASET_NAME="${DATASET_NAME:-mew_analytics}"
RAW_POWER_STAT_TABLE="${RAW_POWER_STAT_TABLE:-POWER_STAT}"
RAW_GENERATOR_TABLE="${RAW_GENERATOR_TABLE:-GENERATOR_READINGS}"
DATAFORM_REPO="${DATAFORM_REPO:-mew-grid-pipeline}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-grid-stress-alerts}"

echo "==> Retrieving DAGs GCS prefix for Composer environment '${COMPOSER_ENV_NAME}' (${REGION})..."
DAG_GCS_PREFIX="$(gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --format="value(config.dagGcsPrefix)")"

if [[ -z "${DAG_GCS_PREFIX}" ]]; then
    echo "ERROR: Could not resolve DAG GCS prefix for Composer environment '${COMPOSER_ENV_NAME}'." >&2
    exit 1
fi

echo "==> Target DAGs Bucket: ${DAG_GCS_PREFIX}"
echo "==> Uploading DAGs from ${SCRIPT_DIR}/dags/..."
gcloud storage cp "${SCRIPT_DIR}/dags/"*.py "${DAG_GCS_PREFIX}/" --project="${PROJECT_ID}"

echo "==> Setting Airflow Variables for runtime parameterization..."
for VAR_PAIR in \
    "gcp_project_id=${PROJECT_ID}" \
    "gcp_location=${REGION}" \
    "bq_dataset=${DATASET_NAME}" \
    "raw_power_stat_table=${RAW_POWER_STAT_TABLE}" \
    "raw_generator_table=${RAW_GENERATOR_TABLE}" \
    "dataform_repository=${DATAFORM_REPO}" \
    "pubsub_alert_topic=${PUBSUB_TOPIC}"; do
    KEY="${VAR_PAIR%%=*}"
    VAL="${VAR_PAIR#*=}"
    gcloud composer environments run "${COMPOSER_ENV_NAME}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" \
        variables set -- "${KEY}" "${VAL}" >/dev/null 2>&1 || true
done

echo "==> Verifying DAG import status in Cloud Composer..."
gcloud composer environments run "${COMPOSER_ENV_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    dags list-import-errors || true

echo "==> DAG synchronization complete!"
