#!/usr/bin/env bash
# Extracted from .github/workflows/verify-release.yml
{
  echo ""
  echo "### Run result"
  echo ""
  if [[ "$VERIFY_OUTCOME" == success ]]; then echo "All required checks passed."; else echo "Verification failed; see the failing step and check rows above."; fi
  echo ""
  echo "- Package Run ID: $PACKAGE_RUN_ID"
  [[ -z "$VERSION" ]] || echo "- Version: $VERSION"
  [[ -z "$RELEASE_TAG" ]] || echo "- Tag: $RELEASE_TAG"
  [[ -z "$COMMIT_SHA" ]] || echo "- Commit SHA: $COMMIT_SHA"
  [[ -z "$BUILD_NUMBER" ]] || echo "- Build Number: $BUILD_NUMBER"
  [[ -z "$PACKAGE_SHA" ]] || echo "- SHA-256: $PACKAGE_SHA"
  [[ -z "$RELEASE_URL" ]] || echo "- Release URL: $RELEASE_URL"
  if [[ "$RELEASE_DRAFT" == true ]]; then echo "- Release state: Draft"; elif [[ "$RELEASE_DRAFT" == false ]]; then echo "- Release state: Published"; fi
} >> "$GITHUB_STEP_SUMMARY"
