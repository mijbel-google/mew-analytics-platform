#!/usr/bin/env bash
# =============================================================================
# MEW Energy Intelligence Platform - Orchestration Deployment Entrypoint
# Migrated from Cloud Workflows/Scheduler to GCP Managed Airflow (Cloud Composer)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Deploying GCP Managed Airflow (Cloud Composer) Environment & DAGs..."
bash "${SCRIPT_DIR}/deploy_composer_env.sh"
bash "${SCRIPT_DIR}/sync_dags.sh"
