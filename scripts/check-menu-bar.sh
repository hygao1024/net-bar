#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
xcrun swiftc -swift-version 6 -O -parse-as-library -I "$bin_dir/Modules" \
    Sources/NetBar/AppDelegate.swift Sources/NetBar/BrandIcon.swift \
    Sources/NetBar/MenuBarPresentation.swift Sources/NetBar/MenuBarSettingsView.swift Sources/NetBar/NetworkAddressesView.swift Sources/NetBar/TrafficView.swift \
    scripts/check-menu-bar.swift "$bin_dir"/NetBarCore.build/*.swift.o -o .build/CheckMenuBar
.build/CheckMenuBar "$@"
