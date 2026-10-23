#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh "$@"
app_dir="$PWD/dist/NetBar.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
arch=arm64
dmg_path="$PWD/dist/NetBar-v${version}-${arch}.dmg"

/usr/bin/codesign --verify --deep --strict "$app_dir"
staging_dir=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto "$app_dir" "$staging_dir/NetBar.app"
ln -s /Applications "$staging_dir/Applications"

/usr/bin/hdiutil create -volname "NetBar $version" -srcfolder "$staging_dir" \
    -fs HFS+ -format UDZO -ov "$dmg_path"
/usr/bin/hdiutil verify "$dmg_path"
printf '已生成：%s\n' "$dmg_path"
