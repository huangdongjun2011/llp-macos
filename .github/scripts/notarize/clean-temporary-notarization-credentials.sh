#!/usr/bin/env bash
# Extracted from .github/workflows/notarize.yml
set +e
rm -f "$API_KEY_FILE"
rm -rf "$WORK_DIR"
echo "Temporary App Store Connect key and notarization workspace removed."
