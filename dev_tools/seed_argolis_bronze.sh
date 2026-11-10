#!/usr/bin/env bash
# =============================================================================
# INTERNAL DEVELOPER SCRIPT (ARGOLIS ONLY)
# Seeds synthetic SCADA data in `electric-load-demo.mew_analytics` using
# BigQuery AI.GENERATE_TABLE to validate ML & Forecasting models.
# =============================================================================
set -euo pipefail

# Clean certificate environment variables for BigQuery CLI compatibility
unset CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE GOOGLE_API_CERTIFICATE_CONFIG CLOUDSDK_CONTEXT_AWARE_CERTIFICATE_CONFIG_FILE_PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-electric-load-demo}"
REGION="${GCP_LOCATION:-europe-west4}"
DATASET_NAME="${DATASET_NAME:-mew_analytics}"

echo "==> [Argolis Dev] Ensuring unified dataset ${PROJECT_ID}:${DATASET_NAME} exists in ${REGION}..."
if ! bq show --project_id="${PROJECT_ID}" "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
    bq --location="${REGION}" mk --dataset \
        --label datacloud:antigravity \
        --description="MEW Unified Energy Intelligence Dataset" \
        "${PROJECT_ID}:${DATASET_NAME}"
fi

echo "==> [Argolis Dev] Executing synthetic SCADA data generation via AI.GENERATE_TABLE..."
sed -e "s/electric-load-demo/${PROJECT_ID}/g" \
    -e "s/mew_analytics/${DATASET_NAME}/g" \
    -e "s/europe-west4/${REGION}/g" \
    "${SCRIPT_DIR}/generate_argolis_synthetic_data.sql" | \
    bq query \
        --project_id="${PROJECT_ID}" \
        --location="${REGION}" \
        --use_legacy_sql=false \
        --label datacloud:antigravity

echo "==> [Argolis Dev] Verifying generated row counts..."
bq query \
    --project_id="${PROJECT_ID}" \
    --location="${REGION}" \
    --use_legacy_sql=false \
    --label datacloud:antigravity \
    "SELECT 'POWER_STAT' AS table_name, COUNT(1) AS row_count FROM \`${PROJECT_ID}.${DATASET_NAME}.POWER_STAT\`
     UNION ALL
     SELECT 'GENERATOR_READINGS' AS table_name, COUNT(1) AS row_count FROM \`${PROJECT_ID}.${DATASET_NAME}.GENERATOR_READINGS\`;"
