# 发布与自动更新

NetBar 使用 [Sparkle](https://sparkle-project.org/documentation/) 检查、下载和安装更新。应用继续使用 ad-hoc signing（临时签名），不需要 Apple 开发者证书。当前发布仅支持 Apple Silicon（`arm64`），要求 macOS 13 或更高版本。

## 签名与信任

`Resources/Info.plist` 的 `SUPublicEDKey` 是客户端信任的 Ed25519（数字签名）公钥。私钥存放在 macOS 登录钥匙串的 `netbar` 账户，GitHub Actions 使用仓库 Secret（机密变量）`SPARKLE_PRIVATE_KEY`。私钥不能进入 Git、发布附件或日志。

更新包在解压前验签，更新清单也必须签名；签名错误不会因时间经过而被忽略。临时签名不能作为更新密钥丢失时的恢复凭据：**务必离线备份原有私钥，不要重新生成或随意更换公钥**。丢失密钥后，旧客户端无法信任新密钥签发的更新，需要手动重新安装。

首次初始化（已有密钥时复用，不覆盖）：

```bash
bash scripts/setup-updates.sh
bash scripts/configure-update-secret.sh
```

第二条命令会修改 `hygao1024/net-bar` 的 GitHub Actions Secret；需要已登录且有仓库权限的 `gh`。它会短暂导出私钥到权限受限的临时目录，通过标准输入上传，退出时删除临时文件。以后更换发布机器应导入备份，而不是生成新密钥。

Sparkle 工具随锁定的 Swift Package Manager（Swift 包管理器）依赖提供：

```bash
# 导出到仓库之外的安全位置；备份文件含私钥，需另行加密和保管。
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account netbar -x /安全备份目录/netbar-update-key
# 在新机器先运行 swift package resolve，再导入同一份备份。
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account netbar -f /安全备份目录/netbar-update-key
```

## 准备版本

1. 更新 `Resources/Info.plist` 的 `CFBundleShortVersionString`（三段产品版本号）及 `CFBundleVersion`（正整数构建号）。二者均需高于上一正式版本；Sparkle 以构建号判断更新。
2. 根据实际变更运行检查。更新机制变动需运行 `bash scripts/check-updates.sh`；设置界面变动需运行预览并同步 README 截图。
3. 本地生成正式产物：

```bash
bash scripts/prepare-release.sh v1.2.0
```

版本参数必须与配置一致。脚本构建 `arm64` 应用、保留 Sparkle 内部工具签名，为外层应用添加临时签名，再生成 DMG（磁盘映像）和签名 appcast（更新清单）。生成目录 `dist/v1.2.0/` 包含：

- `NetBar-v1.2.0-arm64.dmg`：应用和“应用程序”快捷方式。
- `appcast.xml`：版本、构建号、最低系统与硬件要求、包大小、固定版本下载地址和签名。

脚本校验应用签名、磁盘映像、清单签名、版本与包签名。目录已存在时拒绝覆盖，需先检查并移走旧产物再重试。首次依赖解析需要访问 GitHub；本地打包使用钥匙串，CI（持续集成）通过标准输入读取 Secret。

`python3 scripts/check-release-tools.py` 用隔离的 GitHub 命令替身检查标签不一致、构建号与版本倒退、公钥更换等拒绝路径；当前版本的发布目录存在时，同时对真实产物执行错误清单和错误公钥的负向检查，不修改正式配置或产物。

## GitHub 发布

`.github/workflows/release.yml` 在推送 `v*` 标签时运行。确认变更已提交并经过检查后，再明确执行发布：

```bash
git tag v1.2.0
git push origin main
git push origin v1.2.0
```

工作流先验证标签、版本递增及公钥连续性，再测试和打包；在草稿 Release（版本发布）中上传两份附件，全部成功后才公开并标记为最新版本。`prepare-release.sh` 本身不会推送标签或发布。失败时检查 Actions 日志；若已创建草稿而公开失败，确认附件完整后再公开草稿，不要重建或覆盖已经公开的版本附件。

客户端地址固定为 `https://github.com/hygao1024/net-bar/releases/latest/download/appcast.xml`，清单内的安装包地址固定到对应版本标签。正式工作流不发布预发布版本；只有标签而没有完整 Release 附件时，不能提供应用内更新。首次发布之前，检查更新会显示失败，不能视为“已是最新版本”。

## 行为与恢复

自动检查和自动下载默认开启，由 Sparkle 保存用户选择；关闭设置窗口不会中止更新。正常情况下每天检查，后台下载后在应用退出时替换；用户可以通过“检查更新”查看、取消下载或立即安装重启。应用长期不退出时，Sparkle 会按其提醒策略提示安装；需要安装权限时使用原生授权提示。

验签失败、网络中断或下载取消不会替换当前应用。安装与失败清理由 Sparkle 负责；若安装路径不可写、应用仍在磁盘映像中或受到 App Translocation（应用路径随机化）影响，应将应用移到“应用程序”后重新打开。应用身份和偏好域保持 `com.hygao1024.net-speed`；更新后应在固定安装位置检查登录启动状态。首次安装的 Gatekeeper（系统安全检查）限制不由 Sparkle 消除。

`bash scripts/check-updates.sh` 使用随机测试应用标识、临时 Ed25519 密钥和回环 HTTP 服务，运行真实 Sparkle 与产品更新控制器。覆盖设置保存、无更新、取消、网络错误、被篡改的清单和包、手动安装重启、后台下载后退出安装；不写正式钥匙串或登录项。界面交互由测试驱动自动回答。它不代替 GitHub 上首个正式 Release 的实际下载检查，也不验证管理员授权、Gatekeeper 首次安装或真实登录自启。
