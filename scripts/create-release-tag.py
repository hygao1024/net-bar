"""从确认稿创建本地附注标签并核对原文；不推送、不覆盖已有标签。"""
import argparse
import pathlib
import subprocess
import sys


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("tag")
parser.add_argument("notes_file", type=pathlib.Path)
args = parser.parse_args()
try:
    notes = args.notes_file.read_bytes()
    if not notes.decode("utf-8").strip():
        raise SystemExit("发布说明不能为空，未创建标签")
except (OSError, UnicodeDecodeError) as error:
    raise SystemExit(f"无法读取 UTF-8 发布说明，未创建标签：{error}")

# 用参数数组与标准输入传递标签和原文，避免 shell 展开及 Git 默认注释清理。
subprocess.run(
    ["git", "tag", "-a", "--cleanup=verbatim", "-F", "-", "--", args.tag],
    input=notes, check=True,
)
subprocess.run(
    [sys.executable, str(pathlib.Path(__file__).with_name("check-release-notes.py")),
     args.tag, "--notes-file", str(args.notes_file)],
    check=True,
)
print(f"本地标签 {args.tag} 已创建，发布说明与确认稿一致；尚未推送")
