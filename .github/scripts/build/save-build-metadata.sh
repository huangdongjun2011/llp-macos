#!/usr/bin/env bash
# Extracted from .github/workflows/build.yml
set -euo pipefail
cat > artifact/build-metadata.json <<JSON
{
  "commit_sha": "$SOURCE_SHA",
  "version": "$VERSION",
  "build_number": "$BUILD_NUMBER",
  "artifact_name": "$ARTIFACT_NAME",
  "run_id": "$GITHUB_RUN_ID",
  "repository": "$GITHUB_REPOSITORY",
  "workflow": "build"
}
JSON
echo "Build metadata saved: artifact/build-metadata.json"

