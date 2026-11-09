#!/usr/bin/env bash
# Extracted from .github/workflows/test.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
actual="$(git rev-parse HEAD)"
[[ "$actual" == "$EXPECTED_SHA" ]] || fail "Checkout SHA mismatch: requested $EXPECTED_SHA, checked out $actual."
[[ -f mac/api-version ]] || fail "Missing mac/api-version; cannot identify source version."
configured="$(sed -E 's/^API //' mac/api-version | tr -d '\r\n')"
version="$INPUT_VERSION"
if [[ -z "$version" ]]; then
  version="$configured"
  echo "version omitted; using mac/api-version: $version"
fi
[[ "$version" == "$configured" ]] || fail "Version '$version' does not match mac/api-version '$configured'."
echo "sha=$actual" >> "$GITHUB_OUTPUT"
echo "version=$version" >> "$GITHUB_OUTPUT"
echo "Testing commit: $actual"
echo "Version: $version"

