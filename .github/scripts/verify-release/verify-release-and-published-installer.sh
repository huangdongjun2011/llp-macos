#!/usr/bin/env bash
# Extracted from .github/workflows/verify-release.yml
set -uo pipefail
fail() {
  echo "::error::$*"
  echo "| Failure | $* |" >> "$GITHUB_STEP_SUMMARY"
  exit 1
}
check() { echo "| $1 | PASS |" >> "$GITHUB_STEP_SUMMARY"; echo "$1: PASS"; }
mkdir -p "$RELEASE_DIR"
echo "## LLP Release Verification" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| Check | Result |" >> "$GITHUB_STEP_SUMMARY"
echo "|---|---|" >> "$GITHUB_STEP_SUMMARY"
[[ -d "$PACKAGE_DIR" ]] || fail "Package artifact was not downloaded from Run ID $PACKAGE_RUN_ID."
metadata_files=()
while IFS= read -r -d '' file; do metadata_files+=("$file"); done < <(find "$PACKAGE_DIR" -type f -name package-metadata.json -print0)
[[ ${#metadata_files[@]} -eq 1 ]] || fail "Expected exactly one package-metadata.json; found ${#metadata_files[@]}."
metadata="${metadata_files[0]}"
python3 - "$metadata" "$PACKAGE_RUN_ID" "$EXPECTED_REPOSITORY" <<'PY'
import json, os, re, sys
path, run_id, repository = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    data = json.load(file)
errors = []
if str(data.get('package_run_id', '')) != run_id: errors.append('package_run_id mismatch')
if data.get('repository') != repository or data.get('workflow') != 'package': errors.append('Package artifact provenance mismatch')
if not re.fullmatch(r'[0-9a-f]{40}', str(data.get('commit_sha', ''))): errors.append('invalid Commit SHA')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?', str(data.get('version', ''))): errors.append('invalid Version')
if not str(data.get('build_number', '')).isdigit(): errors.append('invalid Build Number')
if data.get('signed') is not True or data.get('notarized') is not True: errors.append('package not marked signed and notarized')
if not re.fullmatch(r'[0-9a-f]{64}', str(data.get('sha256', ''))): errors.append('invalid package SHA-256')
package = data.get('package', '')
if package != os.path.basename(package) or package != f"LLP-{data.get('version')}-macos.zip": errors.append('unexpected package filename')
for key in ('build_run_id', 'sign_run_id', 'notarize_run_id'):
    if not str(data.get(key, '')).isdigit(): errors.append(f'missing {key}')
if errors:
    print('::error::' + '; '.join(errors), file=sys.stderr)
    sys.exit(1)
with open(path + '.outputs', 'w', encoding='utf-8') as out:
    for key in ('commit_sha', 'version', 'build_number', 'build_run_id', 'sign_run_id', 'notarize_run_id', 'package_run_id', 'package', 'sha256'):
        out.write(f'{key}={data[key]}\n')
PY
if [[ $? -ne 0 ]]; then fail "Package metadata is incomplete, malformed, or does not match the specified Package Run."; fi
while IFS='=' read -r key value; do echo "$key=$value" >> "$GITHUB_OUTPUT"; done < "$metadata.outputs"
COMMIT_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit_sha"])' "$metadata")"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$metadata")"
BUILD_NUMBER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build_number"])' "$metadata")"
PACKAGE_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["package"])' "$metadata")"
EXPECTED_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$metadata")"
{
  echo "commit_sha=$COMMIT_SHA"
  echo "version=$VERSION"
  echo "build_number=$BUILD_NUMBER"
  echo "package_sha256=$EXPECTED_SHA"
} >> "$GITHUB_OUTPUT"
TAG="v$VERSION"
check "Package metadata from Run ID $PACKAGE_RUN_ID"

release_json="$RUNNER_TEMP/verify-release-${GITHUB_RUN_ID}.json"
gh release view "$TAG" --json url,isDraft,isPrerelease,tagName,assets > "$release_json" || fail "GitHub Release $TAG does not exist or cannot be read."
RELEASE_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("url", ""))' "$release_json")"
RELEASE_DRAFT="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1])).get("isDraft", False)).lower())' "$release_json")"
RELEASE_TAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tagName", ""))' "$release_json")"
[[ "$RELEASE_TAG" == "$TAG" ]] || fail "Release tag mismatch: expected $TAG, got $RELEASE_TAG."
{
  echo "release_url=$RELEASE_URL"
  echo "release_tag=$TAG"
  echo "draft=$RELEASE_DRAFT"
} >> "$GITHUB_OUTPUT"
check "Release exists: $RELEASE_URL"

git init release-repo
git -C release-repo remote add origin "https://github.com/$GH_REPO.git"
gh auth setup-git
git -C release-repo fetch --no-tags origin "refs/tags/$TAG:refs/tags/$TAG" || fail "Release tag $TAG is missing from the repository."
actual_tag_commit="$(git -C release-repo rev-parse "$TAG^{commit}")"
[[ "$actual_tag_commit" == "$COMMIT_SHA" ]] || fail "Tag $TAG points to $actual_tag_commit, expected package commit $COMMIT_SHA."
check "Tag $TAG points to expected Commit SHA $COMMIT_SHA"

asset_check="$(python3 - "$release_json" "$PACKAGE_NAME" <<'PY'
import json, sys
release, package = sys.argv[1:]
names = {asset.get('name') for asset in json.load(open(release)).get('assets', [])}
expected = {package, package + '.sha256'}
missing = sorted(expected - names)
if missing:
    raise SystemExit('missing Release assets: ' + ', '.join(missing))
print('ok')
PY
)" || fail "Release is missing the expected ZIP installer or SHA-256 sidecar."
[[ "$asset_check" == ok ]] || fail "Release asset listing verification failed."
check "Release contains $PACKAGE_NAME and $PACKAGE_NAME.sha256"

gh release download "$TAG" --repo "$GH_REPO" --pattern "$PACKAGE_NAME" --pattern "$PACKAGE_NAME.sha256" --dir "$RELEASE_DIR" || fail "Could not download the actual installer and checksum from GitHub Release."
[[ -s "$RELEASE_DIR/$PACKAGE_NAME" ]] || fail "Downloaded Release installer is empty or missing."
published_sha="$(shasum -a 256 "$RELEASE_DIR/$PACKAGE_NAME" | awk '{print $1}')"
[[ "$published_sha" == "$EXPECTED_SHA" ]] || fail "Published ZIP SHA-256 $published_sha does not match Package metadata $EXPECTED_SHA."
sidecar_sha="$(awk 'NR==1 {print $1}' "$RELEASE_DIR/$PACKAGE_NAME.sha256")"
[[ "$sidecar_sha" == "$EXPECTED_SHA" ]] || fail "Published SHA-256 sidecar does not match Package metadata."
check "Downloaded Release ZIP SHA-256 matches metadata: $published_sha"
check "Published SHA-256 sidecar matches metadata"

mkdir -p "$RUNNER_TEMP/verify-release-unpacked"
ditto -x -k "$RELEASE_DIR/$PACKAGE_NAME" "$RUNNER_TEMP/verify-release-unpacked" || fail "Could not extract the published installer ZIP."
apps=()
while IFS= read -r -d '' app; do apps+=("$app"); done < <(find "$RUNNER_TEMP/verify-release-unpacked" -type d -name '*.app' -print0)
[[ ${#apps[@]} -eq 1 ]] || fail "Expected exactly one .app in the published ZIP; found ${#apps[@]}."
app="${apps[0]}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)" || fail "Published app Info.plist has no CFBundleShortVersionString."
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null)" || fail "Published app Info.plist has no CFBundleVersion."
[[ "$app_version" == "$VERSION" ]] || fail "App version $app_version does not match package metadata $VERSION."
[[ "$app_build" == "$BUILD_NUMBER" ]] || fail "App build number $app_build does not match package metadata $BUILD_NUMBER."
check "App version and Build Number match metadata ($app_version / $app_build)"

codesign --verify --deep --strict --verbose=2 "$app" || fail "Published app code signature verification failed."
signature="$(codesign -dv --verbose=4 "$app" 2>&1)" || fail "Could not inspect published app signature."
signer="$(printf '%s\n' "$signature" | sed -n 's/^Authority=//p' | head -n 1)"
team="$(printf '%s\n' "$signature" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
[[ "$signer" == "Developer ID Application:"* ]] || fail "Published app is not signed with a Developer ID Application certificate."
[[ -n "$team" && "$team" != "not set" ]] || fail "Published app signature has no TeamIdentifier."
check "codesign Developer ID signature valid ($signer; Team $team)"
spctl --assess --type execute --verbose=4 "$app" || fail "Gatekeeper spctl assessment failed for published app."
check "spctl Gatekeeper assessment accepted"
xcrun stapler validate "$app" || fail "Published app does not have a valid stapled notarization ticket."
check "Apple stapler ticket validates"

{
  echo "package_sha256=$published_sha"
} >> "$GITHUB_OUTPUT"
echo "Release URL: $RELEASE_URL"
echo "Release status: $([[ "$RELEASE_DRAFT" == true ]] && echo Draft || echo Published)"
echo "Tag: $TAG"
echo "Commit SHA: $COMMIT_SHA"
echo "Version: $VERSION"
echo "Build Number: $BUILD_NUMBER"
echo "SHA-256: $published_sha"

