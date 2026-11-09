#!/usr/bin/env bash
# Extracted from .github/workflows/package.yml
{
  echo "## LLP Installer Package"
  echo ""
  echo "- File: $PACKAGE_NAME"
  echo "- SHA-256: $PACKAGE_SHA"
  echo "- Commit: $COMMIT_SHA"
  echo "- Version: $VERSION"
  echo "- Build Number: $BUILD_NUMBER"
  echo "- Build Run ID: $BUILD_RUN_ID"
  echo "- Sign Run ID: $SIGN_RUN_ID"
  echo "- Notarize Run ID: $NOTARIZE_RUN_ID"
  echo "- Package Run ID: $GITHUB_RUN_ID"
} >> "$GITHUB_STEP_SUMMARY"
