#!/usr/bin/env bash
# Extracted from .github/workflows/notarize.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
xcrun stapler staple "$APP_PATH" || fail "Apple accepted notarization, but stapling the ticket to LLP.app failed."
xcrun stapler validate "$APP_PATH" || fail "Stapled notarization ticket validation failed."
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || fail "App signature verification failed after stapling."
mkdir -p "$ARTIFACT_DIR/LLP-notarized"
ditto "$APP_PATH" "$ARTIFACT_DIR/LLP-notarized/LLP.app" || fail "Could not stage notarized app artifact."
cat > "$ARTIFACT_DIR/notarize-metadata.json" <<JSON
{
  "commit_sha": "$COMMIT_SHA",
  "version": "$VERSION",
  "build_number": "$BUILD_NUMBER",
  "build_run_id": "$SOURCE_BUILD_RUN_ID",
  "sign_run_id": "$SIGN_RUN_ID",
  "notarize_run_id": "$GITHUB_RUN_ID",
  "notary_submission_id": "$SUBMISSION_ID",
  "repository": "$GITHUB_REPOSITORY",
  "workflow": "notarize",
  "identity": "$IDENTITY",
  "team_id": "$TEAM_ID",
  "notarized": true,
  "stapled": true
}
JSON
echo "Apple accepted and stapled LLP $VERSION (build $BUILD_NUMBER), commit $COMMIT_SHA."

