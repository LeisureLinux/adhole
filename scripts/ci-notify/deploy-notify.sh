#!/usr/bin/env bash
# deploy-notify.sh — 把 ci-notify 模板批量部署到指定仓库，并设置 Secrets。
#
# 用法：
#   ./deploy-notify.sh --repos LeisureLinux/adhole LeisureLinux/happy-downloader ...
#   ./deploy-notify.sh --all-public        # 所有公开仓库（默认跳过已有 ci-notify 的）
#   ./deploy-notify.sh --repos ... --dry  # 只打印计划，不写远端
#
# 前置：gh 已登录且有 repo + workflow scope；本机 ~/.pi/agent/telegram-status.json 存着 bot 凭据。
# 注意：token 从本地文件读取，永不出现在命令行参数 / git 提交 / 日志里。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/workflow-notify.yml.example"
CRED="${TELEGRAM_CRED_FILE:-$HOME/.pi/agent/telegram-status.json}"
TARGET_PATH=".github/workflows/ci-notify.yml"
REPOS=()
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repos) shift; while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do REPOS+=("$1"); shift; done ;;
    --all-public)
      mapfile -t REPOS < <(gh repo list LeisureLinux --limit 200 --json nameWithOwner,isPrivate \
                           --jq '.[] | select(.isPrivate==false) | .nameWithOwner')
      ;;
    --dry) DRY=1; shift ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -r "$CRED" ] || { echo "ERROR: 读不到凭据 $CRED" >&2; exit 1; }
[ -r "$TEMPLATE" ] || { echo "ERROR: 缺模板 $TEMPLATE" >&2; exit 1; }
[ ${#REPOS[@]} -gt 0 ] || { echo "ERROR: 未指定仓库" >&2; exit 2; }

# 只读进变量，不 echo、不写文件
read -r BOT_TOKEN CHAT_ID < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); print(d["botToken"], d["chatId"])
' "$CRED")

for repo in "${REPOS[@]}"; do
  echo "=== $repo ==="
  if gh api "repos/$repo/contents/$TARGET_PATH" --jq '.name' >/dev/null 2>&1; then
    echo "  已存在 $TARGET_PATH，跳过（如需更新模板请手动覆盖）"
    continue
  fi
  echo "  设置 secrets + 追加 $TARGET_PATH"
  if [ "$DRY" = 1 ]; then continue; fi
  # secrets：用 stdin，避免 token 出现在 ps / shell history
  printf '%s' "$BOT_TOKEN" | gh secret set TELEGRAM_BOT_TOKEN --repo "$repo" >/dev/null
  printf '%s' "$CHAT_ID"   | gh secret set TELEGRAM_CHAT_ID   --repo "$repo" >/dev/null
  # 用 Contents API 提交文件（不依赖本地 clone；base64 在内存里）
  B64=$(base64 -w0 "$TEMPLATE")
  python3 - "$repo" "$B64" <<'PY'
import json, os, subprocess, sys
repo, b64 = sys.argv[1], sys.argv[2]
payload = {
    "message": "ci: add Telegram CI result notification",
    "content": b64,
    "branch": None,
}
# 先查默认分支
branch = subprocess.check_output(
    ["gh","api",f"repos/{repo}","--jq",".default_branch"], text=True).strip()
payload["branch"] = branch
p = subprocess.run(
    ["gh","api","-X","PUT",f"repos/{repo}/contents/.github/workflows/ci-notify.yml",
     "--input","-"],
    input=json.dumps(payload), text=True, capture_output=True)
if p.returncode:
    print("  提交失败:", p.stderr.strip()[:300]); raise SystemExit(1)
print("  已提交到", branch)
PY
done
echo "完成。首次 workflow 完成后会收到 Telegram 消息。"
