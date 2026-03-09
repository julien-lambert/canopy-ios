#!/bin/sh
set -euo pipefail

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"
xcodebuild -project JardinForet.xcodeproj -scheme JardinForet -destination "$DESTINATION" -enableCodeCoverage YES test
