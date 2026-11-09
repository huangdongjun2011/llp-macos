#!/usr/bin/env bash
# Extracted from .github/workflows/notarize.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
metadata="$(find "$RUNNER_TEMP/signed-artifacts" -type f -name sign-metadata.json -print -quit)"
[[ -n "$metadata" ]] || fail "Sign artifact is missing sign-metadata.json; refusing to notarize an unverified app."
python3 - "$metadata" "$SIGN_RUN_ID" "$EXPECTED_REPOSITORY" <<'PY'
import json, re, sys
path, run_id, repository = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    data = json.load(file)
if str(data.get('sign_run_id', '')) != run_id:
    raise SystemExit('::error::Sign metadata Run ID does not match sign_run_id.')
if data.get('repository') != repository:
    raise SystemExit('::error::Sign artifact belongs to a different repository.')
if not re.fullmatch(r'[0-9a-f]{40}', str(data.get('commit_sha', ''))):
    raise SystemExit('::error::Sign metadata has an invalid Commit SHA.')
if not data.get('version') or not str(data.get('build_number', '')).isdigit():
    raise SystemExit('::error::Sign metadata is missing version/build number.')
if not str(data.get('source_build_run_id', '')).isdigit():
    raise SystemExit('::error::Sign metadata is missing the source Build Run ID.')
if not str(data.get('identity', '')).startswith('Developer ID Application:') or not data.get('team_id'):
    raise SystemExit('::error::Sign metadata does not identify a Developer ID signed app.')
with open(path + '.outputs', 'w', encoding='utf-8') as out:
    for key in ('source_build_run_id', 'commit_sha', 'version', 'build_number', 'identity', 'team_id'):
        out.write(f'{key}={data[key]}\n')
print(f"Verified signed artifact: commit={data['commit_sha']} version={data['version']} build={data['build_number']}")
PY
while IFS='=' read -r key value; do echo "$key=$value" >> "$GITHUB_OUTPUT"; done < "$metadata.outputs"
zip="$(find "$(dirname "$metadata")" -type f -name '*-signed.zip' -print -quit)"
[[ -n "$zip" ]] || fail "Sign artifact is missing the signed .app ZIP."
mkdir -p "$WORK_DIR/unpacked"
ditto -x -k "$zip" "$WORK_DIR/unpacked" || fail "Could not extract the signed app ZIP."
app="$(find "$WORK_DIR/unpacked" -type d -name '*.app' -print -quit)"
[[ -n "$app" ]] || fail "Signed ZIP does not contain a .app bundle."
codesign --verify --deep --strict --verbose=2 "$app" || fail "The downloaded app signature is invalid; refusing to notarize it."
signature="$(codesign -dv --verbose=4 "$app" 2>&1)" || fail "Could not inspect the app signature."
identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["identity"])' "$metadata")"
team="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["team_id"])' "$metadata")"
grep -F "Authority=$identity" <<< "$signature" >/dev/null || fail "App signer does not match the recorded Developer ID Application identity."
grep -F "TeamIdentifier=$team" <<< "$signature" >/dev/null || fail "App Team ID does not match sign metadata."
printf '%s' "$API_KEY_BASE64" | base64 --decode > "$API_KEY_FILE" || fail "APPLE_NOTARY_API_KEY_BASE64 is not valid base64."
chmod 600 "$API_KEY_FILE"
echo "app=$app" >> "$GITHUB_OUTPUT"
echo "verified_zip=$zip" >> "$GITHUB_OUTPUT"
echo "Sign artifact and Developer ID signature verified."

