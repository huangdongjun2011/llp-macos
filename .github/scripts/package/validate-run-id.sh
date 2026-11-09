#!/usr/bin/env bash
# Extracted from .github/workflows/package.yml
set -euo pipefail
[[ "$NOTARIZE_RUN_ID" =~ ^[0-9]+$ ]] || { echo "::error::notarize_run_id must be a numeric GitHub Actions Run ID."; exit 1; }
echo "Preparing package from Notarize Run ID $NOTARIZE_RUN_ID."

