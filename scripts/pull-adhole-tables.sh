#!/usr/bin/env bash
# pull-adhole-tables.sh — 从固定 Release `adhole` 拉取分类后的资产，按角色更新本机。
#
# 核心约定：
#   * CI 只发布分类后的表（cn / noncn），112 万条原始全表是中间产物，不下载、不发布。
#   * full = cn + noncn 合并；mail3 需要 full，在本地合并，不额外发布第三个 zst。
#   * 先只拉 adhole-assets.sha256（~400B）。与本地记录相同 → 什么也不做，直接退出。
#     不同 → 才下载所需资产，逐个 sha256 校验，全部通过后再 install + 重启服务。
#   * mail2 连不上 GitHub，由 wpad-02 代拉全部资产后 scp 给它。
#
# 角色：
#   wpad-02  自拉全部资产；本机用 cn 表 + geo-domestic.srs；重启 unbound-domestic / sing-box
#           并把资产留在 PUSH_DIR 供 mail2 取
#   mail2    从 PUSH_DIR 取 cn.zst / noncn.zst / domestic-domains.txt；
#           产出 cn / noncn 两份表（两个 doh 实例各挂一份）；重启 3 个服务
#   mail3    自拉 cn.zst + noncn.zst；本地合并成 adhole-full.conf；重启 unbound
#
# 部署：/usr/local/bin/pull-adhole-tables.sh
# 状态：/var/lib/adhole-assets.sha256（上次成功应用的清单）
set -euo pipefail

BASE="https://github.com/LeisureLinux/adhole/releases/download/adhole"
ROLE="${1:-}"
DEST="/etc/unbound/adhole"
STATE="/var/lib/adhole-assets.sha256"
PUSH_DIR="${PUSH_DIR:-/var/tmp/adhole-push}"   # wpad-02 落地、mail2 取件
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log() { echo "[$(date '+%F %T')] $*"; }
fetch() { # $1=文件名，下载到 $TMP
  curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 600 \
    "$BASE/$1" -o "$TMP/$1"
}
apply() { sudo -n /usr/bin/install -m 644 "$1" "$2"; }

case "$ROLE" in
  wpad-02|mail2|mail3) ;;
  *) echo "用法: $0 {wpad-02|mail2|mail3}" >&2; exit 2 ;;
esac

# ---- 1. 取清单并比对（唯一入口，无变化即静默退出）----
log "角色=$ROLE 检查远端清单 ..."
if [ "$ROLE" = "mail2" ]; then
  [ -s "$PUSH_DIR/adhole-assets.sha256" ] || { log "ERROR: 缺少 $PUSH_DIR/adhole-assets.sha256（wpad-02 尚未推送）"; exit 1; }
  cp "$PUSH_DIR/adhole-assets.sha256" "$TMP/adhole-assets.sha256"
else
  fetch adhole-assets.sha256
fi
if [ -r "$STATE" ] && cmp -s "$TMP/adhole-assets.sha256" "$STATE"; then
  log "资产无变化，退出"
  exit 0
fi
log "检测到新资产"

# ---- 2. 下载/取件 + 逐个校验 ----
cd "$TMP"
case "$ROLE" in
  wpad-02)
    # 代 mail2 拉全部，反正总共约 2.5MB，且共用同一份清单校验
    FILES=(adhole-cn.conf.zst adhole-noncn.conf.zst domestic-domains.txt geo-domestic.srs geosite-cn.json)
    for f in "${FILES[@]}"; do fetch "$f"; done
    ;;
  mail2)
    FILES=(adhole-cn.conf.zst adhole-noncn.conf.zst domestic-domains.txt)
    for f in "${FILES[@]}"; do
      [ -s "$PUSH_DIR/$f" ] || { log "ERROR: 缺少 $PUSH_DIR/$f"; exit 1; }
      cp "$PUSH_DIR/$f" "$f"
    done
    ;;
  mail3)
    FILES=(adhole-cn.conf.zst adhole-noncn.conf.zst)
    for f in "${FILES[@]}"; do fetch "$f"; done
    ;;
esac
for f in "${FILES[@]}"; do
  grep "  $f\$" adhole-assets.sha256 > remote.sha
  sha256sum -c remote.sha
done

# ---- 3. 解压表（全部成功后才 install，避免半截状态）----
mkdir -p "$TMP/out"
for t in cn noncn; do
  [ -s "adhole-$t.conf.zst" ] || continue
  zstd -d -f --output-dir-flat "$TMP/out" "adhole-$t.conf.zst" >/dev/null
  [ -s "$TMP/out/adhole-$t.conf" ] || { log "ERROR: 解压后缺少 adhole-$t.conf"; exit 1; }
done

# mail3: full = cn + noncn，剔除各自表头，统一加一份
if [ "$ROLE" = "mail3" ]; then
  {
    echo '# Syntax: unbound'
    echo '# Source: GitHub Actions adhole classify (cn + noncn merged locally)'
    echo "# UpdateTime: $(date '+%Y-%m-%dT%H:%M:%S%z')"
    grep -h '^local-zone:' "$TMP/out/adhole-cn.conf" "$TMP/out/adhole-noncn.conf" | sort -u
  } > "$TMP/out/adhole-full.conf"
fi

# ---- 4. 应用 + 只在变化时重启 ----
case "$ROLE" in
  wpad-02)
    apply "$TMP/out/adhole-cn.conf" "$DEST/adhole-cn.conf"
    apply "$TMP/geo-domestic.srs" /etc/sing-box/rules/geo-domestic.srs
    # 落地供 mail2 取件（含清单，mail2 靠它判断有无变化）
    mkdir -p "$PUSH_DIR"
    for f in "${FILES[@]}" adhole-assets.sha256; do cp -f "$f" "$PUSH_DIR/$f"; done
    # mail2 连不上 GitHub，由本机推送过去
    ssh -o ConnectTimeout=10 -o BatchMode=yes axu@mail2 "mkdir -p $PUSH_DIR"
    scp -o ConnectTimeout=10 "${FILES[@]/#/$TMP/}" adhole-assets.sha256 \
      "axu@mail2:$PUSH_DIR/" >/dev/null
    log "已推送资产到 mail2:$PUSH_DIR"
    log "重启 unbound-domestic / sing-box"
    sudo -n /usr/bin/systemctl restart unbound-domestic sing-box
    ;;
  mail2)
    apply "$TMP/out/adhole-cn.conf" "$DEST/adhole-cn.conf"
    apply "$TMP/out/adhole-noncn.conf" "$DEST/adhole-noncn.conf"
    apply "$TMP/domestic-domains.txt" /etc/dnsdist/domestic-domains.txt
    log "重启 unbound-doh / unbound-doh-foreign / dnsdist"
    sudo -n /usr/bin/systemctl restart unbound-doh unbound-doh-foreign dnsdist
    ;;
  mail3)
    apply "$TMP/out/adhole-full.conf" "$DEST/adhole-full.conf"
    log "重启 unbound"
    sudo -n /usr/bin/systemctl restart unbound
    ;;
esac

# 全部成功后才记录状态
apply adhole-assets.sha256 "$STATE" 2>/dev/null || cp -f adhole-assets.sha256 "$STATE"
log "完成"
