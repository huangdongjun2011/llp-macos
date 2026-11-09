#!/usr/bin/env bash
# Extracted from .github/workflows/build.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
[[ -f mac/api-version ]] || fail "Missing mac/api-version; cannot determine application version."
configured="$(sed -E 's/^API //' mac/api-version | tr -d '\r\n')"
version="$INPUT_VERSION"
if [[ -z "$version" ]]; then
  version="$configured"
  echo "version omitted; using mac/api-version: $version"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || fail "Invalid version '$version'; expected semantic version such as 1.2.3."
[[ "$version" == "$configured" ]] || fail "Version '$version' does not match mac/api-version '$configured'."
build_number="$GITHUB_RUN_NUMBER"
artifact_name="llp-macos-${version}-${build_number}"
{
  echo "sha=$SOURCE_SHA"
  echo "version=$version"
  echo "build_number=$build_number"
  echo "artifact_name=$artifact_name"
} >> "$GITHUB_OUTPUT"
echo "Version: $version"
echo "Build number: $build_number (GitHub Actions run number)"
echo "Artifact: $artifact_name"

