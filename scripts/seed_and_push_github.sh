#!/usr/bin/env bash
# =============================================================================
# MEW Energy Intelligence Platform - GitHub Repository Seeding & Sync Script
# Initializes git repository, creates/links `mew-analytics-platform` on GitHub,
# and pushes the main branch.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="${GITHUB_REPO_NAME:-mew-analytics-platform}"
GITHUB_USER="${GITHUB_USER:-}"
REMOTE_URL="${GITHUB_REMOTE_URL:-}"

cd "${REPO_ROOT}"

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: 'git' is not installed. Please install git (e.g., 'sudo apt-get update && sudo apt-get install -y git')." >&2
    exit 1
fi

echo "==> [1/4] Initializing local Git repository in ${REPO_ROOT}..."
if [[ ! -d "${REPO_ROOT}/.git" ]]; then
    git init -b main
else
    git branch -M main
fi

if [[ -z "$(git config user.name || true)" ]]; then
    git config user.name "${GIT_AUTHOR_NAME:-MEW Analytics Platform}"
fi
if [[ -z "$(git config user.email || true)" ]]; then
    git config user.email "${GIT_AUTHOR_EMAIL:-admin@mijbel.altostrat.com}"
fi

echo "==> [2/4] Staging codebase, documentation, and scripts..."
git add .
if ! git diff --cached --quiet; then
    git commit -m "Initial release: MEW Kuwait Energy Intelligence Platform (Dataform, Managed Airflow, BQML, Streamlit App)"
else
    echo "    Working tree clean; no new changes to commit."
fi

echo "==> [3/4] Configuring GitHub remote..."
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "    GitHub CLI (gh) authenticated. Creating/syncing repository '${REPO_NAME}'..."
    if ! git remote get-url origin >/dev/null 2>&1; then
        gh repo create "${REPO_NAME}" --public --source="${REPO_ROOT}" --remote=origin --push
        echo "==> Successfully created and pushed to GitHub via gh CLI!"
        exit 0
    fi
fi

if [[ -z "${REMOTE_URL}" ]]; then
    if git remote get-url origin >/dev/null 2>&1; then
        REMOTE_URL="$(git remote get-url origin)"
    else
        if [[ -z "${GITHUB_USER}" ]]; then
            read -r -p "Enter your GitHub username or organization: " GITHUB_USER
        fi
        REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    fi
fi

if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "${REMOTE_URL}"
else
    git remote add origin "${REMOTE_URL}"
fi

echo "==> [4/4] Pushing branch 'main' to ${REMOTE_URL}..."
git push -u origin main
echo "==> Repository successfully synced to ${REMOTE_URL}"
