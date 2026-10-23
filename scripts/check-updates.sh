#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
source scripts/sparkle-paths.sh
xcrun swiftc -swift-version 6 -parse-as-library \
    -F "$sparkle_frameworks" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    Sources/NetBar/UpdateController.swift scripts/check-updates.swift -o .build/CheckUpdates
python3 scripts/check-updates.py "$sparkle_root" "$sparkle_frameworks"
