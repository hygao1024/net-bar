#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin_dir=$(swift build --show-bin-path)
source scripts/sparkle-paths.sh
xcrun swiftc -parse-as-library \
    -I "$bin_dir/Modules" \
    -F "$sparkle_frameworks" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle_frameworks" \
    Sources/NetBar/UpdateController.swift \
    Sources/NetBar/NetworkAddressesView.swift Sources/NetBar/TrafficView.swift Sources/NetBar/MenuBarSettingsView.swift \
    Sources/NetBar/MenuBarPresentation.swift Sources/NetBar/BrandIcon.swift scripts/render-previews.swift \
    "$bin_dir"/NetBarCore.build/*.swift.o \
    -o .build/RenderTrafficPreviews
.build/RenderTrafficPreviews "$PWD/.build/ui-previews"
