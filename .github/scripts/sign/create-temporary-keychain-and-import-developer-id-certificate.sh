#!/usr/bin/env bash
# Extracted from .github/workflows/sign.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
security create-keychain -p "$KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN" || fail "Could not create temporary signing keychain."
security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_FILE" || fail "Developer ID certificate secret is not valid base64."
chmod 600 "$CERTIFICATE_FILE"
security import "$CERTIFICATE_FILE" -k "$TEMP_KEYCHAIN" -P "$CERTIFICATE_PASSWORD" -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security >/dev/null || fail "Could not import certificate; check certificate secret and password."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN" >/dev/null || fail "Could not authorize codesign to use the imported key."
security list-keychains -d user -s "$TEMP_KEYCHAIN"
identity_list="$(security find-identity -v -p codesigning "$TEMP_KEYCHAIN")"
printf '%s\n' "$identity_list" | grep -F "$SIGNING_IDENTITY" >/dev/null || fail "Imported keychain does not contain the configured Developer ID Application identity."
echo "Temporary signing keychain is ready."

