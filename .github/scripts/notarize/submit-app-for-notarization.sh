#!/usr/bin/env bash
# Extracted from .github/workflows/notarize.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
submission_zip="$WORK_DIR/LLP-notarization-${GITHUB_RUN_ID}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$submission_zip" || fail "Could not create temporary ZIP for Apple notarization."
set +e
xcrun notarytool submit "$submission_zip" --key "$API_KEY_FILE" --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID" --wait --output-format json > "$WORK_DIR/notary-result.json" 2> "$WORK_DIR/notary-submit.stderr"
submit_status=$?
set -e
submission_id="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("id", ""))' "$WORK_DIR/notary-result.json" 2>/dev/null || true)"
status="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("status", ""))' "$WORK_DIR/notary-result.json" 2>/dev/null || true)"
if [[ -n "$submission_id" ]]; then echo "submission_id=$submission_id" >> "$GITHUB_OUTPUT"; fi
if [[ "$submit_status" -ne 0 || "$status" != Accepted ]]; then
  echo "::error::Apple notarization did not return Accepted (status='${status:-unavailable}', exit=$submit_status, submission_id='${submission_id:-unavailable}')."
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" --key "$API_KEY_FILE" --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID" --output-format json > "$WORK_DIR/notary-log.json" 2> "$WORK_DIR/notary-log.stderr" || true
    if [[ -s "$WORK_DIR/notary-log.json" ]]; then
      echo "Apple notarization log follows:"
      cat "$WORK_DIR/notary-log.json"
    else
      echo "Apple notarization log could not be retrieved."
      sed -E 's/(authorization|password|secret|token)[^[:space:]]*/[REDACTED]/Ig' "$WORK_DIR/notary-submit.stderr" >&2 || true
    fi
  else
    sed -E 's/(authorization|password|secret|token)[^[:space:]]*/[REDACTED]/Ig' "$WORK_DIR/notary-submit.stderr" >&2 || true
  fi
  exit 1
fi
echo "Apple notarization accepted: $submission_id"

