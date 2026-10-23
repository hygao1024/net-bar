#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
source scripts/sparkle-paths.sh
xcrun swiftc -swift-version 6 -O -parse-as-library -I "$bin_dir/Modules" \
    -F "$sparkle_frameworks" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle_frameworks" \
    Sources/NetBar/AppDelegate.swift Sources/NetBar/BrandIcon.swift Sources/NetBar/UpdateController.swift Sources/NetBar/MenuBarPresentation.swift Sources/NetBar/MenuBarSettingsView.swift \
    Sources/NetBar/NetworkAddressesView.swift Sources/NetBar/TrafficView.swift scripts/check-panel-memory.swift \
    "$bin_dir"/NetBarCore.build/*.swift.o -o .build/CheckPanelMemory
.build/CheckPanelMemory "$@"
