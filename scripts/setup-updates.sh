#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift package resolve
source scripts/sparkle-paths.sh
configured_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist 2>/dev/null || true)
if [[ -n "$configured_key" ]]; then
    stored_key=$("$sparkle_root/bin/generate_keys" --account netbar -p) || {
        echo '此仓库已有更新公钥，请先从备份导入原有私钥；不能创建替代密钥。' >&2
        exit 1
    }
    if [[ "$stored_key" != "$configured_key" ]]; then
        echo '仓库公钥与钥匙串不一致，拒绝修改。' >&2
        exit 1
    fi
fi
# 私钥保存在专属钥匙串账户，永不写入仓库；重复执行复用同一密钥。
"$sparkle_root/bin/generate_keys" --account netbar
public_key=$("$sparkle_root/bin/generate_keys" --account netbar -p)
python3 - "$public_key" <<'PY'
import base64, pathlib, plistlib, sys
key = sys.argv[1].strip()
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit('更新公钥格式无效。')
path = pathlib.Path('Resources/Info.plist')
data = plistlib.loads(path.read_bytes())
existing = data.get('SUPublicEDKey')
if existing and existing != key:
    raise SystemExit('仓库公钥与钥匙串不一致；拒绝替换，请恢复原有私钥。')
if not existing:
    text = path.read_text().replace('    <key>SUFeedURL</key>', f'    <key>SUPublicEDKey</key><string>{key}</string>\n    <key>SUFeedURL</key>')
    path.write_text(text)
print('更新公钥已配置。请将 Resources/Info.plist 纳入版本管理，并安全备份钥匙串私钥。')
PY
