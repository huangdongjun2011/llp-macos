#!/usr/bin/env bash
# Extracted from .github/workflows/release.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
metadata="$PACKAGE_ROOT/package-metadata.json"
[[ -f "$metadata" ]] || fail "Package artifact is missing package-metadata.json. Refusing to publish without provenance metadata."
python3 - "$metadata" "$PACKAGE_RUN_ID" "$VERSION" "$GITHUB_REPOSITORY" <<'PY'
import json, os, re, sys
path, run_id, version, repository = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    data = json.load(file)
if str(data.get('package_run_id', data.get('run_id', ''))) != run_id:
    raise SystemExit('::error::Package metadata Run ID does not match package_run_id.')
if data.get('repository') != repository or data.get('workflow') != 'package':
    raise SystemExit('::error::Package artifact belongs to another repository.')
if data.get('version') != version:
    raise SystemExit('::error::Requested version does not match Package artifact metadata.')
if not re.fullmatch(r'[0-9a-f]{40}', str(data.get('commit_sha', ''))):
    raise SystemExit('::error::Package metadata has an invalid Commit SHA.')
if not str(data.get('build_number', '')).isdigit():
    raise SystemExit('::error::Package metadata has an invalid Build Number.')
if data.get('signed') is not True or data.get('notarized') is not True:
    raise SystemExit('::error::Package metadata does not confirm successful signing and notarization.')
package = data.get('package')
digest = data.get('sha256')
if not isinstance(package, str) or package != os.path.basename(package):
    raise SystemExit('::error::Package metadata must name a file within the artifact directory.')
if not re.fullmatch(r'[0-9a-f]{64}', str(digest or '')):
    raise SystemExit('::error::Package metadata has an invalid SHA-256.')
with open(path + '.outputs', 'w', encoding='utf-8') as out:
    for key in ('commit_sha', 'version', 'build_number', 'package', 'sha256'):
        out.write(f'{key}={data[key]}\n')
print(f"Package metadata verified: commit={data['commit_sha']} version={version} build={data['build_number']}")
PY
while IFS='=' read -r key value; do echo "$key=$value" >> "$GITHUB_OUTPUT"; done < "$metadata.outputs"

package="$PACKAGE_ROOT/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["package"])' "$metadata")"
[[ -f "$package" ]] || fail "Package artifact file named in package-metadata.json is missing."
actual_sha="$(shasum -a 256 "$package" | awk '{print $1}')"
expected_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$metadata")"
[[ "$actual_sha" == "$expected_sha" ]] || fail "Package SHA-256 mismatch; the artifact may be incomplete or altered."
case "$package" in
  *.pkg)
    pkgutil --check-signature "$package" || fail "Installer package signature verification failed."
    xcrun stapler validate "$package" || fail "Installer package notarization ticket validation failed."
    spctl --assess --type install --verbose=4 "$package" || fail "Gatekeeper rejected the signed/notarized installer."
    ;;
  *.dmg)
    codesign --verify --deep --strict --verbose=2 "$package" || fail "Disk image signature verification failed."
    xcrun stapler validate "$package" || fail "Disk image notarization ticket validation failed."
    spctl --assess --type open --context context:primary-signature --verbose=4 "$package" || fail "Gatekeeper rejected the signed/notarized disk image."
    ;;
  *)
    fail "Unsupported installer extension; Package Workflow must provide a signed, notarized .pkg or .dmg."
    ;;
esac
shasum -a 256 "$package" > "$PACKAGE_ROOT/$(basename "$package").sha256"
echo "package_path=$package" >> "$GITHUB_OUTPUT"
echo "Verified signed and notarized installer: $(basename "$package") ($actual_sha)"

git init release-repo
git -C release-repo remote add origin "https://github.com/$GITHUB_REPOSITORY.git"
git -C release-repo fetch --no-tags origin "refs/tags/$GH_TAG:refs/tags/$GH_TAG" || fail "Required tag $GH_TAG does not exist or could not be fetched. Create it with the separate tag workflow first."
tag_commit="$(git -C release-repo rev-parse "$GH_TAG^{commit}")"
expected_commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit_sha"])' "$metadata")"
[[ "$tag_commit" == "$expected_commit" ]] || fail "Tag $GH_TAG points to $tag_commit, but package metadata is for $expected_commit."
echo "tag_commit=$tag_commit" >> "$GITHUB_OUTPUT"
echo "Verified existing tag $GH_TAG -> $tag_commit"

