#!/usr/bin/env bash
# Extracted from .github/workflows/sign.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
app="$APP_PATH"
entitlements_args=()
if [[ -n "$ENTITLEMENTS_BASE64" ]]; then
  printf '%s' "$ENTITLEMENTS_BASE64" | base64 --decode > "$ENTITLEMENTS_FILE" || fail "APPLE_SIGNING_ENTITLEMENTS_BASE64 is not valid base64."
  chmod 600 "$ENTITLEMENTS_FILE"
  plutil -lint "$ENTITLEMENTS_FILE" >/dev/null || fail "Configured signing entitlements are not a valid plist."
  entitlements_args=(--entitlements "$ENTITLEMENTS_FILE")
  echo "Using configured application entitlements."
else
  echo "No extra entitlements configured; signing with the app's default entitlement set."
fi
codesign --force --deep --options runtime --timestamp "${entitlements_args[@]}" --sign "$SIGNING_IDENTITY" "$app" || fail "Developer ID code signing failed."
codesign --verify --deep --strict --verbose=2 "$app" || fail "codesign verification failed for signed app."
details="$(codesign -dv --verbose=4 "$app" 2>&1)" || fail "Could not inspect the signed app signature."
grep -F "Authority=$SIGNING_IDENTITY" <<< "$details" >/dev/null || fail "Signed app does not report the expected Developer ID Application authority."
grep -F "TeamIdentifier=$TEAM_ID" <<< "$details" >/dev/null || fail "Signed app team ID does not match APPLE_TEAM_ID."
mkdir -p "$ARTIFACT_DIR"
ditto -c -k --sequesterRsrc --keepParent "$app" "$ARTIFACT_DIR/LLP-${VERSION}-${BUILD_NUMBER}-signed.zip" || fail "Could not package the signed app."
cat > "$ARTIFACT_DIR/sign-metadata.json" <<JSON
{
  "source_build_run_id": "$BUILD_RUN_ID",
  "build_artifact": "$BUILD_ARTIFACT",
  "commit_sha": "$COMMIT_SHA",
  "version": "$VERSION",
  "build_number": "$BUILD_NUMBER",
  "sign_run_id": "$GITHUB_RUN_ID",
  "repository": "$GITHUB_REPOSITORY",
  "identity": "$SIGNING_IDENTITY",
  "team_id": "$TEAM_ID"
}
JSON
echo "Signed and verified LLP $VERSION (build $BUILD_NUMBER) from commit $COMMIT_SHA."
echo "Source Build Run ID: $BUILD_RUN_ID; Sign Run ID: $GITHUB_RUN_ID"

