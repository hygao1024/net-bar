"""以随机应用标识和临时密钥验证真实 Sparkle 更新；只访问回环 HTTP 服务。"""
import functools
import http.server
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid

sparkle_root, frameworks = map(pathlib.Path, sys.argv[1:])
sign_tool = sparkle_root.resolve() / "bin/sign_update"
framework = frameworks.resolve() / "Sparkle.framework"
binary = pathlib.Path(".build/CheckUpdates").resolve()


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="update-check-", dir=".build") as temporary:
    root = pathlib.Path(temporary).resolve()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(root)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    key_output = run("swift", "-e", """
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
""")
    private_key, public_key = key_output.splitlines()
    try:
        for mode in ["settings", "current", "cancel", "network", "bad-feed", "bad-archive", "manual", "background"]:
            case = root / mode
            case.mkdir()
            application = case / "installed/NetBarUpdateCheck.app"
            content = application / "Contents"
            (content / "MacOS").mkdir(parents=True)
            (content / "Frameworks").mkdir()
            shutil.copy2(binary, content / "MacOS/CheckUpdates")
            run("ditto", str(framework), str(content / "Frameworks/Sparkle.framework"))
            bundle_id = f"com.hygao1024.netbar.update-check.{uuid.uuid4().hex}"
            feed = f"http://127.0.0.1:{server.server_port}/{mode}/appcast.xml"
            info = {
                "CFBundleIdentifier": bundle_id, "CFBundleName": "NetBar Update Check",
                "CFBundleExecutable": "CheckUpdates", "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0", "LSUIElement": True,
                "LSMinimumSystemVersion": "13.0", "SUPublicEDKey": public_key,
                "SUFeedURL": feed if mode != "network" else feed + ".missing",
                "SUEnableAutomaticChecks": mode == "background", "SUAutomaticallyUpdate": True,
                "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
                "SUSignedFeedFailureExpirationInterval": 0,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
                "NetBarTestRoot": str(case), "NetBarTestMode": mode,
            }
            (content / "Info.plist").write_bytes(plistlib.dumps(info))
            run("codesign", "--force", "--sign", "-", str(application))
            newer = case / "new/NetBarUpdateCheck.app"
            run("ditto", str(application), str(newer))
            info["CFBundleVersion"] = "2"
            info["CFBundleShortVersionString"] = "2.0.0"
            (newer / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            run("codesign", "--force", "--sign", "-", str(newer))
            archive = case / ("update.dmg" if mode == "manual" else "update.zip")
            if mode == "manual":
                run("hdiutil", "create", "-volname", "NetBar Update Check", "-srcfolder", str(newer.parent),
                    "-fs", "HFS+", "-format", "UDZO", str(archive))
            else:
                run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(newer), str(archive))
            signature = run(str(sign_tool), "--ed-key-file", "-", "-p", str(archive), input=private_key)
            version = "1" if mode == "current" else "2"
            xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>NetBar 隔离更新测试</title><item><title>测试版本</title><sparkle:version>{version}</sparkle:version>
<sparkle:shortVersionString>{version}.0.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="http://127.0.0.1:{server.server_port}/{mode}/{archive.name}" length="{archive.stat().st_size}"
type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>
'''
            appcast = case / "appcast.xml"
            appcast.write_text(xml)
            run(str(sign_tool), "--ed-key-file", "-", str(appcast), input=private_key)
            if mode == "bad-feed":
                appcast.write_text(appcast.read_text().replace("测试版本", "篡改版本"))
            if mode == "bad-archive":
                data = bytearray(archive.read_bytes())
                data[50] ^= 1
                archive.write_bytes(data)
            with (case / "process.log").open("w") as log:
                process = subprocess.Popen([str(content / "MacOS/CheckUpdates")], stdout=log, stderr=log)
                try:
                    process.wait(timeout=70)
                    expected = {"settings": "settings", "current": "current", "cancel": "cancelled",
                                "network": "error", "bad-feed": "error", "bad-archive": "error",
                                "manual": "relaunched", "background": "quit-install"}[mode]
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        installed_version = plistlib.loads((content / "Info.plist").read_bytes())["CFBundleVersion"]
                        if (case / expected).exists() and (mode not in ["manual", "background"] or installed_version == "2"):
                            break
                        time.sleep(0.2)
                    else:
                        raise AssertionError(f"{mode}: 未观察到 {expected} 或安装未完成；" + (case / "process.log").read_text())
                    assert not (case / "timeout").exists(), f"{mode}: 测试超时"
                    assert installed_version == ("2" if mode in ["manual", "background"] else "1")
                    if mode == "bad-feed":
                        assert not (case / "found").exists(), "签名无效的清单不得用于发现更新"
                    if mode == "bad-archive":
                        # UI 提前进入“解压”阶段；真正的验签在独立安装器中、读取归档内容之前执行。
                        assert "SUSparkleErrorDomain:3002" in (case / "error-codes").read_text(), (case / "error").read_text()
                        assert not (case / "extracted-data").exists(), "错误签名不得进入归档解压"
                    if mode == "background":
                        assert not (case / "found").exists(), "后台更新不应打开交互提示"
                    print(f"通过：{mode}", flush=True)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                    run("defaults", "delete", bundle_id) if (pathlib.Path.home() / f"Library/Preferences/{bundle_id}.plist").exists() else None
                    cache = pathlib.Path.home() / "Library/Caches" / bundle_id
                    if cache.is_symlink():
                        cache.unlink()
                    elif cache.is_dir():
                        shutil.rmtree(cache)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
print("真实更新检查、取消、签名拒绝、安装重启与后台退出安装全部通过")
