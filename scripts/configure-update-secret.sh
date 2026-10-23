#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sparkle-paths.sh
public_key=$("$sparkle_root/bin/generate_keys" --account netbar -p)
configured_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)
if [[ "$public_key" != "$configured_key" ]]; then
    echo '钥匙串密钥与应用公钥不一致，拒绝配置发布密钥。' >&2
    exit 1
fi
umask 077
key_dir=$(mktemp -d "${TMPDIR:-/tmp}/netbar-update-key.XXXXXX")
trap 'rm -rf "$key_dir"' EXIT
"$sparkle_root/bin/generate_keys" --account netbar -x "$key_dir/private-key"
gh secret set SPARKLE_PRIVATE_KEY --repo hygao1024/net-bar < "$key_dir/private-key"
echo 'GitHub Actions 更新签名密钥已配置，临时导出文件已安排清理。'
