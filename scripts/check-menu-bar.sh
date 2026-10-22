#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
xcrun swiftc -swift-version 6 -O -parse-as-library -I "$bin_dir/Modules" \
    Sources/NetSpeed/AppDelegate.swift Sources/NetSpeed/BrandIcon.swift \
    Sources/NetSpeed/MenuBarPresentation.swift Sources/NetSpeed/MenuBarSettingsView.swift Sources/NetSpeed/TrafficView.swift \
    scripts/check-menu-bar.swift "$bin_dir"/NetSpeedCore.build/*.swift.o -o .build/CheckMenuBar
.build/CheckMenuBar
