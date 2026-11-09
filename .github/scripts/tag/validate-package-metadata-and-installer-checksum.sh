#!/usr/bin/env bash
# Extracted from .github/workflows/tag.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
metadata="$PACKAGE_DIR/package-metadata.json"
[[ -f "$metadata" ]] || fail "Package artifact is missing package-metadata.json."
python3 - "$metadata" "$PACKAGE_RUN_ID" "$EXPECTED_REPOSITORY" <<'PY'
import json, os, re, sys
path, run_id, repository = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    data = json.load(file)
if str(data.get('package_run_id', '')) != run_id:
    raise SystemExit('::error::Package metadata Run ID does not match package_run_id.')
if data.get('repository') != repository or data.get('workflow') != 'package':
    raise SystemExit('::error::Artifact is not a Package Workflow artifact from this repository.')
if not re.fullmatch(r'[0-9a-f]{40}', str(data.get('commit_sha', ''))):
    raise SystemExit('::error::Package metadata contains an invalid Commit SHA.')
version = data.get('version', '')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?', str(version)):
    raise SystemExit('::error::Package metadata contains an invalid Version.')
if not str(data.get('build_number', '')).isdigit():
    raise SystemExit('::error::Package metadata contains an invalid Build Number.')
if data.get('signed') is not True or data.get('notarized') is not True:
    raise SystemExit('::error::Package metadata does not confirm signing and notarization.')
filename = data.get('package')
if not isinstance(filename, str) or filename != os.path.basename(filename) or filename != f'LLP-{version}-macos.zip':
    raise SystemExit('::error::Package metadata has an unexpected installer filename.')
digest = data.get('sha256', '')
if not re.fullmatch(r'[0-9a-f]{64}', str(digest)):
    raise SystemExit('::error::Package metadata contains an invalid SHA-256.')
for key in ('build_run_id', 'sign_run_id', 'notarize_run_id'):
    if not str(data.get(key, '')).isdigit():
        raise SystemExit(f'::error::Package metadata is missing {key}.')
with open(path + '.outputs', 'w', encoding='utf-8') as output:
    for key in ('commit_sha', 'version', 'build_number', 'package', 'sha256'):
        output.write(f'{key}={data[key]}\n')
print(f"Package metadata verified: version={version} commit={data['commit_sha']} build={data['build_number']}")
PY
while IFS='=' read -r key value; do echo "$key=$value" >> "$GITHUB_OUTPUT"; done < "$metadata.outputs"
package="$PACKAGE_DIR/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["package"])' "$metadata")"
[[ -s "$package" ]] || fail "Package installer named in metadata is missing or empty."
actual_sha="$(shasum -a 256 "$package" | awk '{print $1}')"
expected_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$metadata")"
[[ "$actual_sha" == "$expected_sha" ]] || fail "Installer SHA-256 does not match Package metadata."
[[ -f "$package.sha256" ]] || fail "Package SHA-256 sidecar is missing."
sidecar_sha="$(awk 'NR==1 {print $1}' "$package.sha256")"
[[ "$sidecar_sha" == "$expected_sha" ]] || fail "SHA-256 sidecar does not match Package metadata."
echo "package_path=$package" >> "$GITHUB_OUTPUT"
echo "Installer SHA-256 verified: $actual_sha"

