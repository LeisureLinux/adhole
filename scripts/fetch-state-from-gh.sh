#!/usr/bin/env bash
# fetch-state-from-gh.sh — 从 GitHub Release 拉取 Actions 产出的 adhole 表。
# 本机 cron 每周一 06:05 调用；成功后原有 06:40–06:52 分发链路原样复用。
# 用 latest Release 而非按日期拼 tag：workflow 用 UTC 日期，本机周一 06 点时 UTC 仍是周日。
set -euo pipefail
REPO="LeisureLinux/adhole"
DEST="$HOME/mygithub/adhole/data/state"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName)
case "$TAG" in state-*) ;; *) echo "ERROR: latest release 不是 state-* ($TAG)，跳过"; exit 1;; esac
echo "[$(date '+%F %T')] 拉取 $REPO latest = $TAG ..."

cd "$TMP"
gh release download "$TAG" --repo "$REPO" \
   --pattern 'adhole-state.tar.gz' --pattern 'adhole-state.sha256' --clobber
sha256sum -c adhole-state.sha256
tar xzf adhole-state.tar.gz

# 防止拿到过期的旧产物（>8 天报警并退出，下游不分发）
AGE=$(( ( $(date +%s) - $(stat -c %Y "$DEST/.last-fetch" 2>/dev/null || echo 0) ) / 86400 ))

for f in adhole-cn.conf adhole-noncn.conf adhole-full.conf; do
  if cmp -s "$f" "$DEST/$f"; then echo "  $f 无变化"; else
    install -m 644 "$f" "$DEST/$f"; echo "  $f 已更新"
  fi
done
touch "$DEST/.last-fetch"
echo "[$(date '+%F %T')] 完成"
