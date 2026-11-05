#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
read_version
[ "$(uname -s)" = Darwin ] || fail 'Build: LLP requires macOS (AppKit and AVFoundation).'
require swift 'Install Xcode Command Line Tools with xcode-select --install.'
if [ -z "${LLP_API_PYTHON:-}" ]; then
    require python3 'Install Python 3.9 or newer to validate OpenAPI.'
    python3 -m venv "$ROOT/.build/api-tools" || fail 'Validation setup: failed to create Python environment.'
    "$ROOT/.build/api-tools/bin/python3" -m pip install --disable-pip-version-check -r "$ROOT/scripts/requirements-api.txt" || fail 'Validation setup: dependency installation failed. Check Python version and package index access.'
fi
"$ROOT/scripts/validate-api.sh" || fail 'Validate stage failed; build stopped.'
echo 'Generating Swift API...'
swift build --package-path "$ROOT" --target LLPGenerated "$@" || fail 'Generate Swift API stage failed; see Swift diagnostics above.'
echo 'Building LLP-Mac (SwiftPM product LLP)...'
swift build --package-path "$ROOT" --product LLP "$@" || fail 'Build LLP-Mac stage failed; see Swift diagnostics above.'
echo 'LLP-Mac built successfully. Run: swift run --skip-build LLP'
