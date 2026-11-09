#!/usr/bin/env bash
# Extracted from .github/entry.yml
set -eu

case "$TASK" in
  validate|build|test|sign|notarize|package|tag|release|verify-release)
    ;;
  *)
    echo "Unsupported task: $TASK" >&2
    exit 1
    ;;
esac

echo "Task: $TASK"
echo "Commit: $COMMIT_SHA"
echo "Version: $VERSION"

args=(gh workflow run "${TASK}.yml" --ref "$REF")
case "$TASK" in
  validate|build|test)
    if [[ -n "$COMMIT_SHA" ]]; then args+=(-f "commit_sha=$COMMIT_SHA"); fi
    if [[ -n "$VERSION" ]]; then args+=(-f "version=$VERSION"); fi
    ;;
  release)
    if [[ -z "$VERSION" ]]; then
      echo "version is required when task=release" >&2
      exit 1
    fi
    args+=(-f "version=$VERSION")
    ;;
esac
if [[ "$TASK" == validate && -n "$BUILD_NUMBER" ]]; then args+=(-f "build_number=$BUILD_NUMBER"); fi
if [[ "$TASK" == sign && -z "$BUILD_RUN_ID" ]]; then
  echo "build_run_id is required when task=sign" >&2
  exit 1
fi
if [[ "$TASK" == sign ]]; then args+=(-f "build_run_id=$BUILD_RUN_ID"); fi
if [[ "$TASK" == release || "$TASK" == tag || "$TASK" == verify-release ]] && [[ -z "$PACKAGE_RUN_ID" ]]; then
  echo "package_run_id is required when task=$TASK" >&2
  exit 1
fi
if [[ "$TASK" == tag || "$TASK" == release || "$TASK" == verify-release ]]; then args+=(-f "package_run_id=$PACKAGE_RUN_ID"); fi
if [[ "$TASK" == notarize && -z "$SIGN_RUN_ID" ]]; then
  echo "sign_run_id is required when task=notarize" >&2
  exit 1
fi
if [[ "$TASK" == notarize ]]; then args+=(-f "sign_run_id=$SIGN_RUN_ID"); fi
if [[ "$TASK" == package && -z "$NOTARIZE_RUN_ID" ]]; then
  echo "notarize_run_id is required when task=package" >&2
  exit 1
fi
if [[ "$TASK" == package ]]; then args+=(-f "notarize_run_id=$NOTARIZE_RUN_ID"); fi
"${args[@]}"

echo "Workflow dispatch requested."
