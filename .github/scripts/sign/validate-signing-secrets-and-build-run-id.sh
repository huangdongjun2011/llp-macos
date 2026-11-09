#!/usr/bin/env bash
# Extracted from .github/workflows/sign.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
[[ "$BUILD_RUN_ID" =~ ^[0-9]+$ ]] || fail "build_run_id must be a numeric GitHub Actions Run ID."
[[ -n "$CERTIFICATE_BASE64" ]] || fail "Missing GitHub Secret APPLE_DEVELOPER_ID_CERTIFICATE_BASE64."
[[ -n "$CERTIFICATE_PASSWORD" ]] || fail "Missing GitHub Secret APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD."
[[ -n "$SIGNING_IDENTITY" ]] || fail "Missing GitHub Secret APPLE_DEVELOPER_ID_APPLICATION_IDENTITY."
[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || fail "Signing identity must be a Developer ID Application identity, not Apple Development or Mac App Distribution."
[[ -n "$KEYCHAIN_PASSWORD" ]] || fail "Missing GitHub Secret APPLE_SIGNING_KEYCHAIN_PASSWORD."
[[ -n "$TEAM_ID" ]] || fail "Missing GitHub Secret APPLE_TEAM_ID."
echo "Signing inputs are configured for Build Run ID $BUILD_RUN_ID."

