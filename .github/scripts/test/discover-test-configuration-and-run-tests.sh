#!/usr/bin/env bash
# Extracted from .github/workflows/test.yml
set -uo pipefail
fail() { echo "::error::$*"; exit 1; }
result_dir="$RUNNER_TEMP/llp-test-results"
mkdir -p "$result_dir"

projects=()
while IFS= read -r -d '' item; do projects+=("$item"); done < <(find . -type d \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) -print0)
if (( ${#projects[@]} > 0 )); then
  project="${projects[0]}"
  [[ ${#projects[@]} -eq 1 ]] || echo "Multiple Xcode projects/workspaces found; using $project"
  if [[ "$project" == *.xcworkspace ]]; then
    listing="$(xcodebuild -list -json -workspace "$project")" || fail "xcodebuild could not inspect workspace $project."
    schemes="$(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("workspace",{}).get("schemes",[])))' <<< "$listing")"
    project_args=(-workspace "$project")
  else
    listing="$(xcodebuild -list -json -project "$project")" || fail "xcodebuild could not inspect project $project."
    schemes="$(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("project",{}).get("schemes",[])))' <<< "$listing")"
    project_args=(-project "$project")
  fi
  scheme="$(printf '%s\n' "$schemes" | sed '/^$/d' | head -n 1)"
  [[ -n "$scheme" ]] || fail "No shared Xcode scheme found in $project; cannot run tests."
  echo "Using Xcode scheme: $scheme"
  result_bundle="$result_dir/LLP-${SOURCE_SHA}-${GITHUB_RUN_ID}.xcresult"
  set +e
  xcodebuild "${project_args[@]}" -scheme "$scheme" -configuration Debug -destination 'platform=macOS' -resultBundlePath "$result_bundle" test 2>&1 | tee "$result_dir/xcodebuild-test.log"
  status=${PIPESTATUS[0]}
  set -e
  (( status == 0 )) || fail "Xcode tests failed for scheme '$scheme' (exit $status). See xcodebuild-test.log and the .xcresult artifact."
elif [[ -f mac/Package.swift ]]; then
  test_dir="mac/Tests"
  [[ -d "$test_dir" ]] || fail "Swift package found but mac/Tests is missing; no automation tests are configured."
  test_files="$(find "$test_dir" -type f \( -name '*Tests.swift' -o -name '*Test.swift' \) -print -quit)"
  [[ -n "$test_files" ]] || fail "Swift package found but no test source files exist under mac/Tests; refusing to report a false pass."
  result_bundle="$result_dir/LLP-${SOURCE_SHA}-${GITHUB_RUN_ID}.xcresult"
  echo "No Xcode project/workspace found; using Xcode's Swift package scheme LLP and its unit test target."
  set +e
  xcodebuild -packagePath mac -scheme LLP -destination 'platform=macOS' -resultBundlePath "$result_bundle" test 2>&1 | tee "$result_dir/xcodebuild-test.log"
  status=${PIPESTATUS[0]}
  set -e
  (( status == 0 )) || fail "Xcode Swift package tests failed for scheme 'LLP' (exit $status). See xcodebuild-test.log and the .xcresult artifact."
else
  fail "No Xcode project, workspace, or Swift package was found; no automation tests can run."
fi
[[ -d "$result_bundle" ]] || fail "Xcode reported success but did not create the expected .xcresult bundle."
echo "result_bundle=$result_bundle" >> "$GITHUB_OUTPUT"
echo "Tests passed for commit $SOURCE_SHA (version $VERSION)."

