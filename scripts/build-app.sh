#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 0 ]]; then
    echo '用法：bash scripts/build-app.sh（仅构建 arm64）' >&2
    exit 1
fi
swift build -c release --arch arm64
bin_dir=$(swift build -c release --arch arm64 --show-bin-path)
binary="$bin_dir/NetBar"
source scripts/sparkle-paths.sh
xcrun swiftc -parse-as-library Sources/NetBar/BrandIcon.swift scripts/generate-icons.swift -o .build/GenerateIcons
.build/GenerateIcons "$PWD/.build/AppIcon.iconset"
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
app_dir="$PWD/dist/NetBar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp "$binary" "$app_dir/Contents/MacOS/NetBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp .build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp "$sparkle_root/LICENSE" "$app_dir/Contents/Resources/Sparkle-LICENSE.txt"
/usr/bin/ditto "$sparkle_frameworks/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
# 保留 Sparkle 内部工具的原有签名和符号链接；只为外层应用添加临时签名。
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"
printf '已生成：%s\n' "$app_dir"
