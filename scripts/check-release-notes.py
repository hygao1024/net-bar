"""正式发布必须提供带非空说明的附注标签，避免使用提交消息代替版本说明。"""
import argparse
import pathlib
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("tag")
parser.add_argument("--notes-file", type=pathlib.Path, help="核对标签与确认稿是否一致")
args = parser.parse_args()
ref = "refs/tags/" + args.tag
kind = subprocess.run(["git", "cat-file", "-t", ref], capture_output=True, text=True)
if kind.returncode != 0:
    raise SystemExit("发布标签不存在，请先获取对应标签")
if kind.stdout.strip() != "tag":
    raise SystemExit("发布必须使用附注标签，请通过 python3 scripts/create-release-tag.py <标签> <说明文件> 创建")
notes = subprocess.run(
    ["git", "for-each-ref", "--format=%(contents)", ref],
    check=True, capture_output=True,
).stdout
if not notes.strip():
    raise SystemExit("标签的发布说明不能为空")
if args.notes_file is not None:
    expected = args.notes_file.read_bytes()
    if notes.rstrip(b"\n") != expected.rstrip(b"\n"):
        raise SystemExit("标签的发布说明与确认稿不一致，请检查 Markdown 标题和正文；不要推送此标签")
print("附注标签与发布说明检查通过")
