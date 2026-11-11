#!/usr/bin/env bash
# fetch-state-from-gh.sh — 从固定 Release `adhole` 拉取 Actions 产物。
# 与 scripts/main.sh 的 upload/pull 约定一致：固定 tag + 覆盖同名 asset + 固定 URL。
# 本机 cron 06:35 调用；成功后 06:40–06:52 分发链路原样复用。
set -euo pipefail
BASE="https://github.com/LeisureLinux/adhole/releases/download/adhole"
DEST="$HOME/mygithub/adhole/data/state"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[$(date '+%F %T')] 拉取 adhole assets ..."
cd "$TMP"
for f in adhole-state.tar.gz adhole-state.sha256; do
  curl -fsSL --retry 3 --connect-timeout 15 "$BASE/$f" -o "$f"
done
tar xzf adhole-state.tar.gz
sha256sum -c adhole-state.sha256

# 陈旧保护：sha256 文件的 Last-Modified 超过 8 天则告警退出（不覆盖、不触发下游分发）
MAX_AGE_DAYS=${MAX_AGE_DAYS:-8}
LM=$(curl -fsSIL --connect-timeout 15 "$BASE/adhole-state.sha256" \
      | tr -d '\r' | awk -F': ' 'tolower($1)=="last-modified"{print $2}' | tail -1)
if [ -n "$LM" ]; then
  AGE=$(( ( $(date +%s) - $(date -d "$LM" +%s 2>/dev/null || echo 0) ) / 86400 ))
  echo "  asset 年龄: ${AGE} 天 (Last-Modified: $LM)"
  if [ "$AGE" -gt "$MAX_AGE_DAYS" ]; then
    echo "ERROR: 产物超过 ${MAX_AGE_DAYS} 天未更新，拒绝使用（下游分发照旧用现有表）"
    exit 1
  fi
fi

for f in adhole-cn.conf adhole-noncn.conf adhole-full.conf; do
  if cmp -s "$f" "$DEST/$f"; then echo "  $f 无变化"; else
    install -m 644 "$f" "$DEST/$f"; echo "  $f 已更新"
  fi
done
echo "[$(date '+%F %T')] 完成"
