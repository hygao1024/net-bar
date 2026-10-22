#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin_dir=$(swift build --show-bin-path)
xcrun swiftc -parse-as-library \
    -I "$bin_dir/Modules" \
    Sources/NetSpeed/NetworkAddressesView.swift Sources/NetSpeed/TrafficView.swift Sources/NetSpeed/MenuBarSettingsView.swift \
    Sources/NetSpeed/MenuBarPresentation.swift Sources/NetSpeed/BrandIcon.swift scripts/render-previews.swift \
    "$bin_dir"/NetSpeedCore.build/*.swift.o \
    -o .build/RenderTrafficPreviews
.build/RenderTrafficPreviews "$PWD/.build/ui-previews"
