#!/bin/sh
set -euo pipefail

if ! command -v periphery >/dev/null 2>&1; then
  echo "Periphery not installed. Run: brew install peripheryapp/periphery/periphery"
  exit 1
fi

periphery scan --config periphery.yml -- \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.6" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  SWIFTLINT_DISABLED=1
