#!/usr/bin/env bash
# Extracted from .github/workflows/sign.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
metadata="$(find "$RUNNER_TEMP/build-artifacts" -name build-metadata.json -type f -print -quit)"
[[ -n "$metadata" ]] || fail "The specified Build Run artifact has no build-metadata.json; refusing to sign an unverified artifact."
python3 - "$metadata" "$BUILD_RUN_ID" "$EXPECTED_REPOSITORY" <<'PY'
import json, re, sys
path, run_id, repository = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    metadata = json.load(file)
if str(metadata.get('run_id')) != run_id:
    raise SystemExit('::error::Build metadata Run ID does not match build_run_id.')
if metadata.get('repository') != repository or metadata.get('workflow') != 'build':
    raise SystemExit('::error::Build artifact came from a different repository.')
if not re.fullmatch(r'[0-9a-f]{40}', str(metadata.get('commit_sha', ''))):
    raise SystemExit('::error::Build metadata contains an invalid commit SHA.')
if not metadata.get('version') or not str(metadata.get('build_number', '')).isdigit():
    raise SystemExit('::error::Build metadata is missing version/build number.')
with open(path + '.outputs', 'w', encoding='utf-8') as output:
    for key in ('commit_sha', 'version', 'build_number', 'artifact_name'):
        output.write(f'{key}={metadata[key]}\n')
print(f"Verified build artifact: commit={metadata['commit_sha']} version={metadata['version']} build={metadata['build_number']}")
PY
while IFS='=' read -r key value; do echo "$key=$value" >> "$GITHUB_OUTPUT"; done < "$metadata.outputs"
archive="$(find "$(dirname "$metadata")" -type d -name '*.xcarchive' -print -quit)"
[[ -n "$archive" ]] || fail "Build artifact is missing the required .xcarchive. Rerun the updated Build Workflow."
app="$archive/Products/Applications/LLP.app"
[[ -d "$app" ]] || fail "Archive does not contain Products/Applications/LLP.app."
echo "archive=$archive" >> "$GITHUB_OUTPUT"
echo "app=$app" >> "$GITHUB_OUTPUT"
echo "Verified archive for commit $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit_sha"])' "$metadata")."

