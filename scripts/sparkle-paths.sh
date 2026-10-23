#!/bin/bash
# 调用方先运行 swift build / swift package resolve；路径随锁定的 Sparkle 包布局更新。
sparkle_root="$PWD/.build/artifacts/sparkle/Sparkle"
sparkle_frameworks="$sparkle_root/Sparkle.xcframework/macos-arm64_x86_64"
test -d "$sparkle_frameworks/Sparkle.framework" || {
    echo '缺少 Sparkle 构建产物，请先运行 swift package resolve。' >&2
    exit 1
}
