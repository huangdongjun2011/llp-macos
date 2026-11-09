#!/usr/bin/env bash
# Extracted from .github/workflows/release.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
checksum_file="$PACKAGE_ROOT/$(basename "$PACKAGE_FILE").sha256"
release_json="$RUNNER_TEMP/release-${GITHUB_RUN_ID}.json"
if gh release view "$GH_TAG" --json url,isDraft,assets,tagName > "$release_json" 2>/dev/null; then
  existing_tag="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tagName", ""))' "$release_json")"
  [[ "$existing_tag" == "$GH_TAG" ]] || fail "Existing Release tag does not match requested tag."
  is_draft="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1])).get("isDraft", False)).lower())' "$release_json")"
  echo "Found existing release; checking its assets for a safe retry."
else
  gh release create "$GH_TAG" --draft --verify-tag --title "LLP $VERSION" --generate-notes || fail "Could not create Draft Release for $GH_TAG. Verify tag permissions and release state."
  gh release view "$GH_TAG" --json url,isDraft,assets,tagName > "$release_json" || fail "Draft Release was created but could not be read back."
  is_draft=true
fi

upload_missing_asset() {
  local file="$1" name existing_name existing_sha local_sha
  name="$(basename "$file")"
  existing_name="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next((a.get("name", "") for a in d.get("assets",[]) if a.get("name")==sys.argv[2]), ""))' "$release_json" "$name")"
  if [[ -n "$existing_name" ]]; then
    mkdir -p "$RUNNER_TEMP/existing-assets"
    gh release download "$GH_TAG" --repo "$GH_REPO" --pattern "$name" --dir "$RUNNER_TEMP/existing-assets" >/dev/null || fail "Could not verify existing Release asset $name."
    existing_sha="$(shasum -a 256 "$RUNNER_TEMP/existing-assets/$name" | awk '{print $1}')"
    local_sha="$(shasum -a 256 "$file" | awk '{print $1}')"
    [[ "$existing_sha" == "$local_sha" ]] || fail "Release already contains $name with different content; refusing to overwrite it."
    echo "Existing asset verified unchanged: $name"
  else
    [[ "$is_draft" == true ]] || fail "Published Release is missing asset $name; refusing to modify a public release during retry."
    gh release upload "$GH_TAG" "$file" --repo "$GH_REPO" || fail "Could not upload Release asset $name."
    echo "Uploaded Release asset: $name"
  fi
}
upload_missing_asset "$PACKAGE_FILE"
upload_missing_asset "$checksum_file"

gh release view "$GH_TAG" --json url,isDraft,assets,tagName > "$release_json" || fail "Release final verification failed."
release_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$release_json")"
[[ -n "$release_url" ]] || fail "Release URL was not returned."
echo "release_url=$release_url" >> "$GITHUB_OUTPUT"
echo "Draft Release ready: $release_url"
echo "Tag: $GH_TAG"
echo "Commit: $COMMIT_SHA"
echo "Installer: $(basename "$PACKAGE_FILE") (SHA-256 $PACKAGE_SHA)"

