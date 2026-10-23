#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
tag="${1:-v$version}"
if [[ "$tag" != "v$version" || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo '正式版本标签必须为 v<版本号>，并与 Info.plist 的三段版本号一致。' >&2
    exit 1
fi
public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist 2>/dev/null || true)
if [[ -z "$public_key" ]]; then
    echo '缺少更新公钥，请先运行 bash scripts/setup-updates.sh。' >&2
    exit 1
fi
release_dir="$PWD/dist/$tag"
if [[ -e "$release_dir" ]]; then
    echo "发布目录已存在：$release_dir；请检查旧产物后再生成。" >&2
    exit 1
fi
bash scripts/build-dmg.sh
source scripts/sparkle-paths.sh
mkdir "$release_dir"
archive="NetBar-$tag-arm64.dmg"
cp "dist/$archive" "$release_dir/$archive"
signing_args=(--account netbar)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then signing_args=(--ed-key-file -); fi
# 签名工具从标准输入读取 CI 密钥；不把私钥放进进程参数或日志。
printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | "$sparkle_root/bin/generate_appcast" \
    "${signing_args[@]}" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/hygao1024/net-bar/releases/download/$tag/" \
    --link "https://github.com/hygao1024/net-bar/releases/tag/$tag" "$release_dir"
printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | "$sparkle_root/bin/sign_update" \
    "${signing_args[@]}" --verify "$release_dir/appcast.xml"
python3 scripts/verify-release.py "$release_dir" "$public_key"
printf '发布产物已准备：%s\n' "$release_dir"
