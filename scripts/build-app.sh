#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$PWD/dist/NetSpeed.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/NetSpeed" "$app_dir/Contents/MacOS/NetSpeed"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
printf '已生成：%s\n' "$app_dir"
