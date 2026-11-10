#!/usr/bin/env bash
# =============================================================================
# MEW Energy Intelligence Platform - Cloud Composer (Managed Airflow) Provisioner
# Idempotently enables APIs, configures IAM, and provisions Cloud Composer
# =============================================================================
set -euo pipefail

# Clean certificate environment variables for BigQuery CLI compatibility
unset CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE GOOGLE_API_CERTIFICATE_CONFIG CLOUDSDK_CONTEXT_AWARE_CERTIFICATE_CONFIG_FILE_PATH

PROJECT_ID="${GCP_PROJECT_ID:-electric-load-demo}"
REGION="${GCP_LOCATION:-europe-west4}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:-mew-airflow-env}"
DATASET_NAME="${DATASET_NAME:-mew_analytics}"
RAW_POWER_STAT_TABLE="${RAW_POWER_STAT_TABLE:-POWER_STAT}"
RAW_GENERATOR_TABLE="${RAW_GENERATOR_TABLE:-GENERATOR_READINGS}"
DATAFORM_REPO="${DATAFORM_REPO:-mew-grid-pipeline}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-grid-stress-alerts}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-mew-pipeline-sa}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> [1/4] Ensuring required GCP APIs are enabled on ${PROJECT_ID}..."
gcloud services enable \
    composer.googleapis.com \
    dataform.googleapis.com \
    bigquery.googleapis.com \
    pubsub.googleapis.com \
    --project="${PROJECT_ID}"

echo "==> [2/4] Ensuring pipeline Service Account (${SERVICE_ACCOUNT}) and IAM roles..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="MEW Energy Analytics Pipeline Service Account" \
        --project="${PROJECT_ID}"
fi

for ROLE in \
    "roles/composer.worker" \
    "roles/bigquery.dataEditor" \
    "roles/bigquery.jobUser" \
    "roles/dataform.editor" \
    "roles/pubsub.publisher"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT}" \
        --role="${ROLE}" \
        --condition=None \
        --quiet >/dev/null
done

echo "==> [3/4] Ensuring Pub/Sub Alert Topic (${PUBSUB_TOPIC}) exists..."
if ! gcloud pubsub topics describe "${PUBSUB_TOPIC}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud pubsub topics create "${PUBSUB_TOPIC}" --project="${PROJECT_ID}"
else
    echo "    Pub/Sub topic '${PUBSUB_TOPIC}' already exists. Skipping creation."
fi

echo "==> [4/4] Checking Cloud Composer Environment (${COMPOSER_ENV_NAME} in ${REGION})..."
if gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "    Cloud Composer environment '${COMPOSER_ENV_NAME}' already exists. Updating environment variables..."
    gcloud composer environments update "${COMPOSER_ENV_NAME}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" \
        --update-env-variables="GCP_PROJECT_ID=${PROJECT_ID},GCP_LOCATION=${REGION},BQ_DATASET=${DATASET_NAME},DATAFORM_REPOSITORY=${DATAFORM_REPO},PUBSUB_ALERT_TOPIC=${PUBSUB_TOPIC}" || true
else
    echo "    Creating Cloud Composer 3 environment '${COMPOSER_ENV_NAME}' (Small tier)..."
    gcloud composer environments create "${COMPOSER_ENV_NAME}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" \
        --image-version="composer-3-airflow-2.10.2" \
        --environment-size="small" \
        --service-account="${SERVICE_ACCOUNT}" \
        --env-variables="GCP_PROJECT_ID=${PROJECT_ID},GCP_LOCATION=${REGION},BQ_DATASET=${DATASET_NAME},DATAFORM_REPOSITORY=${DATAFORM_REPO},PUBSUB_ALERT_TOPIC=${PUBSUB_TOPIC}"
fi

echo "==> Cloud Composer environment setup complete."
