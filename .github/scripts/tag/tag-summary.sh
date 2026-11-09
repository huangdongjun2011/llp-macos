#!/usr/bin/env bash
# Extracted from .github/workflows/tag.yml
{
  echo "## LLP Git Tag"
  echo ""
  echo "- Tag: $TAG_NAME"
  echo "- Commit: $COMMIT_SHA"
  echo "- Version: $VERSION"
  echo "- Package Run ID: $PACKAGE_RUN_ID"
} >> "$GITHUB_STEP_SUMMARY"
