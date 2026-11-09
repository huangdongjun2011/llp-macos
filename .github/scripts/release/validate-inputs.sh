#!/usr/bin/env bash
# Extracted from .github/workflows/release.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
[[ "$PACKAGE_RUN_ID" =~ ^[0-9]+$ ]] || fail "package_run_id must be a numeric GitHub Actions Run ID."
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || fail "Invalid version '$VERSION'; expected semantic version such as 1.2.3."
echo "Preparing draft release $GH_TAG from Package Run ID $PACKAGE_RUN_ID."

