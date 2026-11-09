#!/usr/bin/env bash
# Extracted from .github/workflows/package.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
[[ -d "$INPUT_DIR" ]] || fail "No artifact was downloaded from Notarize Run ID $NOTARIZE_RUN_ID."
metadata_files=()
while IFS= read -r -d '' file; do metadata_files+=("$file"); done < <(find "$INPUT_DIR" -type f -name notarize-metadata.json -print0)
[[ ${#metadata_files[@]} -eq 1 ]] || fail "Expected exactly one notarize-metadata.json; found ${#metadata_files[@]}."
metadata="${metadata_files[0]}"
python3 - "$metadata" "$NOTARIZE_RUN_ID" "$EXPECTED_REPOSITORY" <<'PY'
import json, re, sys
path, run_id, repository = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    data = json.load(file)
if str(data.get('notarize_run_id', '')) != run_id:
    raise SystemExit('::error::Notarize metadata Run ID does not match notarize_run_id.')
if data.get('repository') != repository or data.get('workflow') != 'notarize':
    raise SystemExit('::error::Notarized artifact belongs to a different repository.')
if not re.fullmatch(r'[0-9a-f]{40}', str(data.get('commit_sha', ''))):
    raise SystemExit('::error::Notarize metadata has an invalid Commit SHA.')
if not data.get('version') or not str(data.get('build_number', '')).isdigit():
    raise SystemExit('::error::Notarize metadata is missing Version or Build Number.')
if not str(data.get('build_run_id', '')).isdigit() or not str(data.get('sign_run_id', '')).isdigit():
    raise SystemExit('::error::Notarize metadata is missing Build Run ID or Sign Run ID.')
if not str(data.get('notary_submission_id', '')).strip():
    raise SystemExit('::error::Notarize metadata is missing Apple submission ID.')
if data.get('notarized') is not True or data.get('stapled') is not True:
    raise SystemExit('::error::Notarize metadata does not confirm Accepted notarization and stapling.')
if not str(data.get('identity', '')).startswith('Developer ID Application:') or not data.get('team_id'):
    raise SystemExit('::error::Notarize metadata does not identify a Developer ID signed app.')
with open(path + '.outputs', 'w', encoding='utf-8') as out:
    for key in ('commit_sha', 'version', 'build_number', 'build_run_id', 'sign_run_id', 'notarize_run_id', 'identity', 'team_id'):
        out.write(f'{key}={data[key]}\n')
print(f"Verified notarization metadata: commit={data['commit_sha']} version={data['version']} build={data['build_number']}")
PY
while IFS='=' read -r key value; do echo "$key=$value" >> "$GITHUB_OUTPUT"; done < "$metadata.outputs"

apps=()
while IFS= read -r -d '' app; do apps+=("$app"); done < <(find "$INPUT_DIR" -type d -name '*.app' -print0)
[[ ${#apps[@]} -eq 1 ]] || fail "Expected exactly one notarized .app bundle; found ${#apps[@]}."
app="${apps[0]}"
codesign --verify --deep --strict --verbose=2 "$app" || fail "Downloaded app has an invalid code signature."
signature="$(codesign -dv --verbose=4 "$app" 2>&1)" || fail "Could not inspect downloaded app signature."
identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["identity"])' "$metadata")"
team="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["team_id"])' "$metadata")"
grep -F "Authority=$identity" <<< "$signature" >/dev/null || fail "App signer does not match notarization metadata."
grep -F "TeamIdentifier=$team" <<< "$signature" >/dev/null || fail "App Team ID does not match notarization metadata."
xcrun stapler validate "$app" || fail "The app has no valid stapled Apple notarization ticket."
echo "app=$app" >> "$GITHUB_OUTPUT"
echo "Verified Developer ID signature and stapled Apple ticket."

