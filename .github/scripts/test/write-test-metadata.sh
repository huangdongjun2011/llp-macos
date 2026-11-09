#!/usr/bin/env bash
# Extracted from .github/workflows/test.yml
mkdir -p "$RUNNER_TEMP/llp-test-results"
cat > "$RUNNER_TEMP/llp-test-results/test-metadata.json" <<JSON
{
  "commit_sha": "$SOURCE_SHA",
  "version": "$VERSION",
  "run_id": "$GITHUB_RUN_ID",
  "repository": "$GITHUB_REPOSITORY"
}
JSON

