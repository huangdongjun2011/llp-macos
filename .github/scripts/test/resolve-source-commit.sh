#!/usr/bin/env bash
# Extracted from .github/workflows/test.yml
set -euo pipefail
sha="$INPUT_SHA"
if [[ -z "$sha" ]]; then
  sha="$GITHUB_SHA"
  echo "commit_sha omitted; using selected workflow ref: $sha"
fi
[[ "$sha" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "::error::commit_sha must be a full 40-character SHA-1."; exit 1; }
sha="$(printf %s "$sha" | tr '[:upper:]' '[:lower:]')"
echo "sha=$sha" >> "$GITHUB_OUTPUT"
echo "Test source commit: $sha"

