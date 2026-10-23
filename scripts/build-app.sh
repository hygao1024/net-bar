#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
xcrun swiftc -parse-as-library Sources/NetBar/BrandIcon.swift scripts/generate-icons.swift -o .build/GenerateIcons
.build/GenerateIcons "$PWD/.build/AppIcon.iconset"
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
app_dir="$PWD/dist/NetBar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/NetBar" "$app_dir/Contents/MacOS/NetBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp .build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$app_dir"
printf '已生成：%s\n' "$app_dir"
