#!/bin/bash
# Shared helpers; compatible with macOS Bash 3.2.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail() { echo "error: $*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || fail "Required tool '$1' is missing. $2"; }
read_version() {
    [ -f "$ROOT/api-version" ] || fail "Missing $ROOT/api-version (expected API x.y.z)."
    API_VERSION=$(cat "$ROOT/api-version")
    if [[ "$API_VERSION" =~ ^API\ ([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?)$ ]]; then
        API_VERSION=${BASH_REMATCH[1]}
    else
        fail "Invalid api-version: expected a single line such as API 1.0.0."
    fi
}
