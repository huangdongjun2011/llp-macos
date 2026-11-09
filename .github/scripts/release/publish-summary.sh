#!/usr/bin/env bash
# Extracted from .github/workflows/release.yml
{
  echo "## LLP Draft Release"
  echo ""
  echo "- URL: $RELEASE_URL"
  echo "- Tag: $GH_TAG"
  echo "- Commit: $COMMIT_SHA"
  echo "- Installer: $(basename "$PACKAGE_FILE")"
  echo "- Package Run ID: $PACKAGE_RUN_ID"
} >> "$GITHUB_STEP_SUMMARY"
