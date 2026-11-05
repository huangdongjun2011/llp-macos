#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
read_version
[ -s "$ROOT/../common/apis/llp-apis.yaml" ] || fail 'Missing or empty common/apis/llp-apis.yaml in the repository.'
PYTHON=${LLP_API_PYTHON:-$ROOT/.build/api-tools/bin/python3}
[ -x "$PYTHON" ] || fail 'Validation Python is missing. Run scripts/build.sh to prepare tools, or set LLP_API_PYTHON to a Python with scripts/requirements-api.txt installed.'
"$PYTHON" "$ROOT/scripts/validate-api.py" "$ROOT/../common/apis/llp-apis.yaml" "$API_VERSION" || fail 'Validate stage failed; see the OpenAPI diagnostic above.'
