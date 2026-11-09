#!/usr/bin/env bash
# Extracted from .github/workflows/validate.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
cd source

[[ -f mac/Package.swift ]] || fail "Missing mac/Package.swift; this repository uses Swift Package Manager, not a checked-in Xcode project."
[[ -d mac/Sources/LLP ]] || fail "Missing mac/Sources/LLP executable sources."
[[ -d mac/Tests/LLPTests ]] || fail "Missing mac/Tests/LLPTests."
[[ -f mac/Package.resolved ]] || fail "Missing mac/Package.resolved; dependency versions are not pinned."
[[ -f mac/api-version ]] || fail "Missing mac/api-version version configuration."

swift package --package-path mac dump-package > package.json || fail "Swift package manifest is invalid."
python3 -c 'import json,sys; p=json.load(open("package.json")); products={x.get("name") for x in p.get("products",[])}; targets={x.get("name") for x in p.get("targets",[])}; ok=p.get("name")=="LLP" and "LLP" in products and "LLP" in targets; print("Swift package structure valid: package=LLP, product=LLP, executable target=LLP" if ok else "::error::Expected package, product, and executable target named LLP.", file=sys.stdout if ok else sys.stderr); sys.exit(0 if ok else 1)' || fail "Swift package does not expose the expected LLP scheme/product."

if [[ -e mac/LLP.xcodeproj || -e mac/LLP.xcworkspace ]]; then
  echo "Optional Xcode project/workspace found."
  xcodebuild -list -json -project mac/LLP.xcodeproj > xcode-projects.json 2> xcode-list.err || {
    cat xcode-list.err >&2
    fail "xcodebuild could not inspect the checked-in Xcode project."
  }
  grep -q '"LLP"' xcode-projects.json || fail "Xcode project does not expose an LLP scheme."
else
  echo "No .xcodeproj/.xcworkspace is checked in; validating the repository's SwiftPM LLP scheme instead."
fi
echo "Validated Xcode/SwiftPM project metadata at $SOURCE_SHA"
