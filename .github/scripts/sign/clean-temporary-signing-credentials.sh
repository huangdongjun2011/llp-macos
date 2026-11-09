#!/usr/bin/env bash
# Extracted from .github/workflows/sign.yml
set +e
if [[ -f "$TEMP_KEYCHAIN" ]]; then
  security delete-keychain "$TEMP_KEYCHAIN" >/dev/null 2>&1
fi
rm -f "$CERTIFICATE_FILE" "$ENTITLEMENTS_FILE"
echo "Temporary keychain and signing credential files removed."
