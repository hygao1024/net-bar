"""正式发布必须提供带非空说明的附注标签，避免使用提交消息代替版本说明。"""
import subprocess
import sys


ref = "refs/tags/" + sys.argv[1]
kind = subprocess.run(["git", "cat-file", "-t", ref], capture_output=True, text=True)
if kind.returncode != 0:
    raise SystemExit("发布标签不存在，请先获取对应标签")
if kind.stdout.strip() != "tag":
    raise SystemExit("发布必须使用附注标签，请通过 git tag -a -F <说明文件> 创建")
notes = subprocess.run(
    ["git", "for-each-ref", "--format=%(contents:subject)%0a%(contents:body)", ref],
    check=True, capture_output=True, text=True,
).stdout
if not notes.strip():
    raise SystemExit("标签的发布说明不能为空")
print("附注标签与发布说明检查通过")
