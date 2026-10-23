"""发布前对照最新正式 Release，防止标签、构建号或签名公钥倒退。"""
import base64
import json
import plistlib
import re
import subprocess
import sys


def gh(*arguments):
    return subprocess.run(["gh", *arguments], check=True, capture_output=True, text=True).stdout


info = plistlib.load(open("Resources/Info.plist", "rb"))
version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
if not re.fullmatch(r"\d+\.\d+\.\d+", version) or sys.argv[1] != "v" + version or not build.isdecimal():
    raise SystemExit("标签必须与正式版本号一致，构建号必须为正整数")
if int(build) < 1:
    raise SystemExit("构建号必须为正整数")
releases = json.loads(gh("release", "list", "--repo", "hygao1024/net-bar", "--limit", "1",
                         "--exclude-drafts", "--exclude-pre-releases", "--json", "tagName"))
if releases:
    previous_tag = releases[0]["tagName"]
    previous_file = json.loads(gh("api", "repos/hygao1024/net-bar/contents/Resources/Info.plist",
                                  "--method", "GET", "-f", "ref=" + previous_tag))
    previous = plistlib.loads(base64.b64decode(previous_file["content"]))
    if int(build) <= int(previous["CFBundleVersion"]):
        raise SystemExit("构建号必须高于最新正式 Release")
    if tuple(map(int, version.split("."))) <= tuple(map(int, previous["CFBundleShortVersionString"].split("."))):
        raise SystemExit("版本号必须高于最新正式 Release")
    if previous.get("SUPublicEDKey") and previous["SUPublicEDKey"] != info.get("SUPublicEDKey"):
        raise SystemExit("更新公钥发生变化；临时签名应用不可通过普通发布轮换信任密钥")
print("正式发布版本检查通过")
