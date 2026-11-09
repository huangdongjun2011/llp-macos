#!/usr/bin/env bash
# Extracted from .github/workflows/package.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
mkdir -p "$OUTPUT_DIR"
package_name="LLP-${VERSION}-macos.zip"
package_path="$OUTPUT_DIR/$package_name"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$package_path" || fail "Could not create ZIP with macOS ditto."
[[ -s "$package_path" ]] || fail "ditto produced an empty installer ZIP."
shasum -a 256 "$package_path" > "$package_path.sha256" || fail "Could not create package SHA-256 file."
package_sha="$(awk '{print $1}' "$package_path.sha256")"
cat > "$OUTPUT_DIR/package-metadata.json" <<JSON
{
  "package_run_id": "$GITHUB_RUN_ID",
  "repository": "$GITHUB_REPOSITORY",
  "workflow": "package",
  "commit_sha": "$COMMIT_SHA",
  "version": "$VERSION",
  "build_number": "$BUILD_NUMBER",
  "build_run_id": "$BUILD_RUN_ID",
  "sign_run_id": "$SIGN_RUN_ID",
  "notarize_run_id": "$NOTARIZE_RUN_ID",
  "signed": true,
  "notarized": true,
  "package": "$package_name",
  "sha256": "$package_sha"
}
JSON
echo "package_name=$package_name" >> "$GITHUB_OUTPUT"
echo "package_sha=$package_sha" >> "$GITHUB_OUTPUT"
echo "Created $package_name (SHA-256 $package_sha)."
echo "Source Build Run ID: $BUILD_RUN_ID; Sign Run ID: $SIGN_RUN_ID; Notarize Run ID: $NOTARIZE_RUN_ID; Package Run ID: $GITHUB_RUN_ID"

