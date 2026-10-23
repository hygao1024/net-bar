"""发布守卫负向检查：不连接 GitHub，不创建标签或更改正式配置。"""
import base64
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile

repository = pathlib.Path(__file__).resolve().parent.parent
actual = plistlib.loads((repository / "Resources/Info.plist").read_bytes())
source = dict(actual, CFBundleVersion="6", CFBundleShortVersionString="1.2.0")

with tempfile.TemporaryDirectory(prefix="release-check-", dir=repository / ".build") as temporary:
    root = pathlib.Path(temporary)
    (root / "Resources").mkdir()
    fake_gh = root / "gh"
    fake_gh.write_text("""#!/usr/bin/env python3
import os, sys
print(os.environ['TEST_RELEASES'] if sys.argv[1] == 'release' else os.environ['TEST_PREVIOUS'])
""")
    fake_gh.chmod(0o700)
    previous = dict(source, CFBundleVersion="5", CFBundleShortVersionString="1.1.0")
    environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       TEST_RELEASES=json.dumps([{"tagName": "v1.1.0"}]),
                       TEST_PREVIOUS=json.dumps({"content": base64.b64encode(plistlib.dumps(previous)).decode()}))

    def check(name, info, tag, expected_error=None):
        (root / "Resources/Info.plist").write_bytes(plistlib.dumps(info))
        result = subprocess.run(["python3", str(repository / "scripts/check-release-version.py"), tag],
                                cwd=root, env=environment, capture_output=True, text=True)
        if expected_error is None:
            assert result.returncode == 0, result.stderr
        else:
            assert result.returncode != 0 and expected_error in result.stderr, result.stderr
        print("通过：" + name)

    check("正式版本递增", source, "v1.2.0")
    check("标签不一致被拒绝", source, "v9.0.0", "标签必须")
    check("重复构建号被拒绝", dict(source, CFBundleVersion="5"), "v1.2.0", "构建号必须高于")
    check("版本号倒退被拒绝", dict(source, CFBundleShortVersionString="1.0.0"), "v1.0.0", "版本号必须高于")
    check("公钥更换被拒绝", dict(source, SUPublicEDKey="different-key"), "v1.2.0", "公钥发生变化")
    environment["TEST_RELEASES"] = "[]"
    check("首次发布", source, "v1.2.0")

    # 对当前真实发布产物植入错误元数据，并确认签名与配置不一致也会拒绝。
    artifacts = repository / "dist" / ("v" + actual["CFBundleShortVersionString"])
    if artifacts.exists():
        output = root / "artifacts"
        output.mkdir()
        for asset in artifacts.iterdir():
            if asset.suffix == ".dmg":
                (output / asset.name).symlink_to(asset)
        xml = (artifacts / "appcast.xml").read_text()
        (output / "appcast.xml").write_text(xml.replace(f"<sparkle:version>{actual['CFBundleVersion']}</sparkle:version>", "<sparkle:version>0</sparkle:version>"))
        result = subprocess.run(["python3", "scripts/verify-release.py", str(output), source["SUPublicEDKey"]],
                                cwd=repository, capture_output=True, text=True)
        assert result.returncode != 0 and "不一致" in result.stderr
        print("通过：清单版本不一致被拒绝")
        (output / "appcast.xml").write_text(xml)
        result = subprocess.run(["python3", "scripts/verify-release.py", str(output), base64.b64encode(bytes(32)).decode()],
                                cwd=repository, capture_output=True, text=True)
        assert result.returncode != 0 and "签名与应用公钥不匹配" in result.stderr
        print("通过：包签名与公钥不一致被拒绝")
    else:
        print("未检查发布产物：请先运行 prepare-release.sh，再执行清单与签名负向检查")
