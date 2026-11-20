#!/usr/bin/env bash
# Parse the workflow_dispatch context JSON and export only this workflow's fields.
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }
[[ -n "${CONTEXT:-}" ]] || fail "context is required and must contain a JSON object."
[[ -n "${GITHUB_OUTPUT:-}" && -n "${GITHUB_ENV:-}" ]] || fail "GITHUB_OUTPUT and GITHUB_ENV must be set."

python3 - "$CONTEXT" "$GITHUB_OUTPUT" "$GITHUB_ENV" "$@" <<'PY'
import json
import re
import sys

raw, output_path, env_path, *specs = sys.argv[1:]
try:
    context = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"::error::context must be valid JSON: {exc.msg} at character {exc.pos}.", file=sys.stderr)
    sys.exit(1)
if not isinstance(context, dict):
    print("::error::context must be a JSON object.", file=sys.stderr)
    sys.exit(1)

values = []
for spec in specs:
    mode, key = spec.split(":", 1)
    if not re.fullmatch(r"[a-z][a-z0-9_]*", key):
        print(f"::error::Invalid context key declaration: {key}", file=sys.stderr)
        sys.exit(1)
    value = context.get(key, "")
    if value is None:
        value = ""
    if not isinstance(value, (str, int, float)) or isinstance(value, bool):
        print(f"::error::context.{key} must be a string or number.", file=sys.stderr)
        sys.exit(1)
    value = str(value)
    if "\n" in value or "\r" in value:
        print(f"::error::context.{key} must be a single-line value.", file=sys.stderr)
        sys.exit(1)
    if mode == "required" and not value.strip():
        print(f"::error::Missing required context parameter: {key}.", file=sys.stderr)
        sys.exit(1)
    values.append((key, value))

with open(output_path, "a", encoding="utf-8") as outputs, open(env_path, "a", encoding="utf-8") as env:
    for key, value in values:
        outputs.write(f"{key}={value}\n")
        env.write(f"{key.upper()}={value}\n")
PY
