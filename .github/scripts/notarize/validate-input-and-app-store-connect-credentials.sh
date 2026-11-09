#!/usr/bin/env bash
# Extracted from .github/workflows/notarize.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
[[ "$SIGN_RUN_ID" =~ ^[0-9]+$ ]] || fail "sign_run_id must be a numeric GitHub Actions Run ID."
[[ -n "$API_KEY_BASE64" ]] || fail "Missing GitHub Secret APPLE_NOTARY_API_KEY_BASE64."
[[ -n "$API_KEY_ID" ]] || fail "Missing GitHub Secret APPLE_NOTARY_API_KEY_ID."
[[ -n "$API_ISSUER_ID" ]] || fail "Missing GitHub Secret APPLE_NOTARY_API_ISSUER_ID."
echo "App Store Connect API key credentials are configured for Sign Run ID $SIGN_RUN_ID."

