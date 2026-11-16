#!/usr/bin/env bash
# =============================================================================
# OPTIONAL SCRIPT: Dataform GitHub Subtree Branch & Airflow Git Mode Setup
#
# Use ONLY if your organization uses GitHub and you connected your Dataform
# repository (`mew-grid-pipeline`) to GitHub.
#
# What this script does (idempotently):
#   1. Splits `dataform/` into a dedicated `dataform` branch and pushes it to
#      GitHub (`origin/dataform`) so `workflow_settings.yaml` sits at branch root.
#   2. Updates the Dataform repository's default branch to `dataform` (if
#      already connected to GitHub) and verifies compilation.
#   3. Configures `DATAFORM_GIT_COMMITISH=dataform` on Managed Airflow Gen 3
#      (Cloud Composer) if the environment exists.
# =============================================================================
set -euo pipefail

unset CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE GOOGLE_API_CERTIFICATE_CONFIG CLOUDSDK_CONTEXT_AWARE_CERTIFICATE_CONFIG_FILE_PATH

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-electric-load-demo}"
REGION="${GCP_LOCATION:-europe-west4}"
DATAFORM_REPO="${DATAFORM_REPO:-mew-grid-pipeline}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:-mew-airflow-env}"
DATAFORM_BRANCH="${DATAFORM_BRANCH:-dataform}"

cd "${REPO_ROOT}"

echo "==> [1/3] Splitting 'dataform/' subtree and pushing to origin/${DATAFORM_BRANCH}..."
SUBTREE_SHA="$(git subtree split --prefix=dataform HEAD)"
git push origin "${SUBTREE_SHA}:refs/heads/${DATAFORM_BRANCH}" --force

echo "==> [2/3] Checking Dataform repository '${DATAFORM_REPO}' (${REGION})..."
TOKEN="$(gcloud auth print-access-token)"
REPO_PATH="projects/${PROJECT_ID}/locations/${REGION}/repositories/${DATAFORM_REPO}"
BASE_URL="https://dataform.googleapis.com/v1beta1"

REPO_JSON="$(curl -s -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/${REPO_PATH}")"
if echo "${REPO_JSON}" | python3 -c "import sys, json; d=json.load(sys.stdin); sys.exit(0 if d.get('gitRemoteSettings', {}).get('url') else 1)"; then
    echo "    Updating defaultBranch to '${DATAFORM_BRANCH}' on '${DATAFORM_REPO}'..."
    UPDATED_SETTINGS="$(echo "${REPO_JSON}" | python3 -c "
import sys, json
d = json.load(sys.stdin)['gitRemoteSettings']
d['defaultBranch'] = '${DATAFORM_BRANCH}'
for k in ('tokenStatus', 'effectiveDefaultBranch'):
    d.pop(k, None)
print(json.dumps({'gitRemoteSettings': d}))
")"
    curl -s -X PATCH \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/${REPO_PATH}?updateMask=gitRemoteSettings.defaultBranch" \
        -d "${UPDATED_SETTINGS}" >/dev/null

    echo "    Verifying Dataform compilation from gitCommitish='${DATAFORM_BRANCH}'..."
    COMP_RES="$(curl -s -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/${REPO_PATH}/compilationResults" \
        -d "{\"gitCommitish\":\"${DATAFORM_BRANCH}\"}")"
    echo "${COMP_RES}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'name' in d and not d.get('compilationErrors'):
    print('    Compilation succeeded:', d['name'])
else:
    print('    Compilation warning/error:', json.dumps(d, indent=2))
    sys.exit(1)
"
else
    echo "    Note: '${DATAFORM_REPO}' does not have GitHub connected yet. Skipping Dataform branch update."
fi

echo "==> [3/3] Updating Managed Airflow Gen 3 (${COMPOSER_ENV_NAME}) to compile from '${DATAFORM_BRANCH}'..."
if gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --quiet >/dev/null 2>&1; then
    gcloud composer environments update "${COMPOSER_ENV_NAME}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" \
        --update-env-variables="DATAFORM_GIT_COMMITISH=${DATAFORM_BRANCH}" \
        --quiet
    echo "    Managed Airflow updated with DATAFORM_GIT_COMMITISH=${DATAFORM_BRANCH}."
else
    echo "    Composer environment '${COMPOSER_ENV_NAME}' not found in '${REGION}'. Skipping."
fi

echo "==> Optional Dataform GitHub setup complete!"
