#!/usr/bin/env bash
# Extracted from .github/workflows/tag.yml
set -euo pipefail
[[ "$PACKAGE_RUN_ID" =~ ^[0-9]+$ ]] || { echo "::error::package_run_id must be a numeric GitHub Actions Run ID."; exit 1; }
echo "Resolving release commit and version from Package Run ID $PACKAGE_RUN_ID."

