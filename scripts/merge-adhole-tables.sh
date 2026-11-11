#!/usr/bin/env bash
# merge-adhole-tables.sh — 合并 cn + noncn 表为全表（给 mail2 用）
#
# 输出：data/state/adhole-full.conf
# 条目：local-zone: "域名" always_null（与 unbound local-zone 格式一致）
# 去重：同一域名可能同时出现在 cn 和 noncn（分类随 IP 变化而漂移）
#
# 用法：bash merge-adhole-tables.sh [输出路径]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$SCRIPT_DIR/../data/state"
CN="$STATE_DIR/adhole-cn.conf"
NONCN="$STATE_DIR/adhole-noncn.conf"
OUT="${1:-$STATE_DIR/adhole-full.conf}"

[[ -f "$CN"    ]] || { echo "ERROR: 缺少 $CN"; exit 1; }
[[ -f "$NONCN" ]] || { echo "ERROR: 缺少 $NONCN"; exit 1; }

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# 只取 local-zone 行，去掉注释头；用 sed 提取域名后排序去重
{
  grep '^local-zone:' "$CN"
  grep '^local-zone:' "$NONCN"
} | sed 's/^local-zone: "\(.*\)" always_null$/\1/' | sort -u > "$TMP"

COUNT=$(wc -l < "$TMP")
{
  echo "# adhole 全量过滤表（cn + noncn 合并去重）"
  echo "# 生成时间: $(date '+%F %T')"
  echo "# 条目数: $COUNT"
  awk '{print "local-zone: \"" $0 "\" always_null"}' "$TMP"
} > "$OUT"

echo "已生成: $OUT  ($COUNT 条, $(du -h "$OUT" | cut -f1))"
