#!/usr/bin/env bash
# Extracted from .github/workflows/validate.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }

sha="$INPUT_SHA"
if [[ -z "$sha" ]]; then
  sha="$GITHUB_SHA"
  echo "commit_sha was not supplied; using dispatched ref commit $sha"
fi
[[ "$sha" =~ ^[0-9a-fA-F]{40}$ ]] || fail "commit_sha must be a full 40-character SHA-1; received '${sha:-<empty>}'"
sha="$(printf %s "$sha" | tr '[:upper:]' '[:lower:]')"

repo_url="$SERVER_URL/$REPOSITORY.git"
git init source
git -C source remote add origin "$repo_url"
git -C source fetch --no-tags --depth=1 origin "$sha" || fail "Commit $sha could not be fetched from $repo_url. Check the SHA and repository access."
fetched="$(git -C source rev-parse FETCH_HEAD^{commit})"
[[ "$fetched" == "$sha" ]] || fail "Fetched commit mismatch: requested $sha, received $fetched"
git -C source checkout --detach "$sha"

version="$INPUT_VERSION"
if [[ -z "$version" ]]; then
  [[ -f source/mac/api-version ]] || fail "Missing mac/api-version; cannot infer version."
  version="$(sed -E 's/^API //' source/mac/api-version | tr -d '\r\n')"
  echo "version was not supplied; inferred API version $version from mac/api-version"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || fail "Invalid version '$version'; expected semantic version such as 1.2.3 or 1.2.3-beta.1"
[[ -f source/mac/api-version ]] || fail "Missing source/mac/api-version."
configured="$(sed -E 's/^API //' source/mac/api-version | tr -d '\r\n')"
[[ "$configured" == "$version" ]] || fail "Version mismatch: input is '$version', but mac/api-version declares '$configured'."

if [[ -n "$INPUT_BUILD_NUMBER" ]]; then
  [[ "$INPUT_BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "build_number must contain digits only when provided."
  echo "Optional build_number accepted: $INPUT_BUILD_NUMBER"
else
  echo "No build_number supplied; validation does not require manual build numbering."
fi

echo "sha=$sha" >> "$GITHUB_OUTPUT"
echo "version=$version" >> "$GITHUB_OUTPUT"
echo "repo_url=$repo_url" >> "$GITHUB_OUTPUT"
echo "Validated source repository: $repo_url"
echo "Validated commit: $sha"
echo "Validated version: $version"

