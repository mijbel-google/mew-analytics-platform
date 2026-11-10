#!/usr/bin/env bash
# =============================================================================
# MEW Energy Intelligence Platform - Cloud Run Data App Deployment Script
# Idempotently creates Artifact Registry repository, builds container, and deploys
# =============================================================================
set -euo pipefail

# Clean certificate environment variables for BigQuery CLI compatibility
unset CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE GOOGLE_API_CERTIFICATE_CONFIG CLOUDSDK_CONTEXT_AWARE_CERTIFICATE_CONFIG_FILE_PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-electric-load-demo}"
REGION="${GCP_LOCATION:-europe-west4}"
DATASET_ID="${DATASET_NAME:-${DATASET_ID:-mew_analytics}}"
SERVICE_NAME="${SERVICE_NAME:-mew-scada-intelligence-hub}"
REPO_NAME="${REPO_NAME:-mew-data-apps}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-mew-pipeline-sa}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> [1/4] Configuring GCP Project (${PROJECT_ID}) & enabling Cloud Run / Build APIs..."
gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    bigquery.googleapis.com \
    aiplatform.googleapis.com \
    --project="${PROJECT_ID}"

echo "==> [2/4] Ensuring Service Account (${SERVICE_ACCOUNT}) & Artifact Registry (${REPO_NAME})..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="MEW Energy Analytics Pipeline Service Account" \
        --project="${PROJECT_ID}"
fi

for ROLE in \
    "roles/bigquery.dataViewer" \
    "roles/bigquery.jobUser" \
    "roles/aiplatform.user"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT}" \
        --role="${ROLE}" \
        --condition=None \
        --quiet >/dev/null
done

if ! gcloud artifacts repositories describe "${REPO_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud artifacts repositories create "${REPO_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --project="${PROJECT_ID}" \
        --description="MEW Container Repository"
fi

# Sync data_agent instructions into data_app build context for self-contained container build
mkdir -p "${SCRIPT_DIR}/data_agent"
if [[ -d "${SCRIPT_DIR}/../data_agent" ]]; then
    cp -f "${SCRIPT_DIR}/../data_agent/"* "${SCRIPT_DIR}/data_agent/" 2>/dev/null || true
fi

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${SERVICE_NAME}:latest"

echo "==> [3/4] Building and Submitting Container via Cloud Build..."
gcloud builds submit "${SCRIPT_DIR}" \
    --tag="${IMAGE_URI}" \
    --project="${PROJECT_ID}" \
    --quiet

echo "==> [4/4] Deploying to Cloud Run (Dataset: ${DATASET_ID})..."
gcloud run deploy "${SERVICE_NAME}" \
    --image="${IMAGE_URI}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --platform=managed \
    --service-account="${SERVICE_ACCOUNT}" \
    --cpu=2 \
    --memory=4Gi \
    --min-instances=0 \
    --max-instances=10 \
    --concurrency=80 \
    --set-env-vars="GCP_PROJECT_ID=${PROJECT_ID},GCP_LOCATION=${REGION},DATASET_ID=${DATASET_ID},GOLD_DATASET=${DATASET_ID}" \
    --allow-unauthenticated \
    --quiet || \
gcloud run deploy "${SERVICE_NAME}" \
    --image="${IMAGE_URI}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --platform=managed \
    --service-account="${SERVICE_ACCOUNT}" \
    --cpu=2 \
    --memory=4Gi \
    --min-instances=0 \
    --max-instances=10 \
    --concurrency=80 \
    --set-env-vars="GCP_PROJECT_ID=${PROJECT_ID},GCP_LOCATION=${REGION},DATASET_ID=${DATASET_ID},GOLD_DATASET=${DATASET_ID}" \
    --quiet

echo "==> Deployment Complete!"
gcloud run services describe "${SERVICE_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --format='value(status.url)'
