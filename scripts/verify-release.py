"""验证清单元数据和公钥对应的包签名；验签由系统 CryptoKit 执行。"""
import base64
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

directory = pathlib.Path(sys.argv[1]).resolve()
key = sys.argv[2]
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit("更新公钥格式无效")
info = plistlib.loads(pathlib.Path("Resources/Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
if not build.isdecimal() or int(build) < 1:
    raise SystemExit("构建号必须为递增的正整数")
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(directory / "appcast.xml").getroot()
items = root.findall("channel/item")
if len(items) != 1:
    raise SystemExit("正式发布清单必须恰好包含当前版本")
item = items[0]
enclosure = item.find("enclosure")
archive = directory / f"NetBar-v{version}-arm64.dmg"
architectures = subprocess.check_output(["lipo", "-archs", "dist/NetBar.app/Contents/MacOS/NetBar"], text=True).strip()
if architectures != "arm64":
    raise SystemExit("发布应用必须仅包含 arm64 架构")
expected_url = f"https://github.com/hygao1024/net-bar/releases/download/v{version}/{archive.name}"
if (item.findtext("sparkle:version", namespaces=namespace) != build
    or item.findtext("sparkle:shortVersionString", namespaces=namespace) != version
    or item.findtext("sparkle:hardwareRequirements", namespaces=namespace) != "arm64"
    or item.findtext("sparkle:minimumSystemVersion", namespaces=namespace) != info["LSMinimumSystemVersion"]
    or enclosure is None or enclosure.get("url") != expected_url
    or int(enclosure.get("length", "0")) != archive.stat().st_size):
    raise SystemExit("发布清单的版本、系统与硬件要求、下载地址或大小与产物不一致")
signature = enclosure.get(f'{{{namespace["sparkle"]}}}edSignature', "")
subprocess.run(["swift", "scripts/verify-update-signature.swift", key, str(archive), signature], check=True)
print("发布清单和安装包签名验证通过")
