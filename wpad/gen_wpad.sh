#!/usr/bin/env bash
set -euo pipefail

# goproxy http 代理的端口(wpad 必须启用 http 代理)
HTTP_PORT=8888
# The SS_CFG file should be chmod 640, root:axu
SS_CFG="/etc/shadowsocks-libev/my_ss.json"

WPAD="/var/www/html/wpad/wpad.dat"
USER_RULE_FILE="/tmp/custom-user-rules.txt"

# 使用可靠的 GFWList 镜像源 (避免 raw.githubusercontent.com 被墙导致下载到 HTML 页面)
GFWLIST_URL="https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt"

# ##########################
chk_pkg() {
	# 检查必备的软件包
	PROG="libpacparser1 haveged"
	if ! echo "$PROG" | xargs dpkg-query -W >/dev/null 2>&1; then
        echo "Error: install $PROG first!"
        exit 1
    fi
	if ! command -v genpac >/dev/null 2>&1; then
        echo "Error: install genpac by run # pip3 install genpac"
        exit 1
    fi
	if ! command -v pactester >/dev/null 2>&1; then
        echo "Error: install libpacparser1 first."
        exit 1
    fi
}

check_local_port() {
	if ! nc -zv 127.0.0.1 "$PRX_PORT" >/dev/null 2>&1; then
        echo "Error: 请检查本地代理的服务端口：$PRX_PORT"
        exit 1
    fi
}

# Main Prog.
chk_pkg

# Host IP
HIP=$(hostname -I | awk '{print $1}')
if ! nc -zv localhost 53 >/dev/null 2>&1; then
    echo "Error: local dns not up"
    exit 2
fi
HNAME="wpad.lan"

IP=$(dig -4 +short "$HNAME" @localhost) || true
if [ -z "$IP" ]; then
	echo "Error: $HNAME record was not setup correctly! "
	echo "Run: \"unbound-control local_data $HNAME. A $HIP\" to add $HNAME record and re-run this script."
	exit 1
fi
echo "$HNAME. was setup as $IP"

if [ ! -r "$SS_CFG" ]; then
    echo "Error: missing shadowsocks config file, $SS_CFG"
    exit 1
fi
PRX_PORT=$(jq -r ".local_port" < "$SS_CFG") || true
if [ -z "$PRX_PORT" ]; then
    echo "Error: Missing proxy port number"
    exit 1
fi
echo "Info: proxy port: $PRX_PORT"
PROXY="socks5 $IP:$PRX_PORT"

if [ ! -w "$WPAD" ]; then
    echo "Error: $WPAD file not writable!"
    exit 2
fi

PAC="PROXY $IP:$HTTP_PORT; $PROXY"
check_local_port
echo "Info: generating $WPAD with --pac-proxy=\"$PAC\" ..."

# 备份现有的 wpad.dat
cp "$WPAD" "$WPAD.bak" 2>/dev/null || true

# 1. 动态生成/更新自定义规则文件 (提取 AI 与 Telegram 等追加规则)
cat <<'EOF' > "$USER_RULE_FILE"
! AI & LLM Services
||chatgpt.com
||openai.com
||oaistatic.com
||oaiusercontent.com
||claude.ai
||anthropic.com
||aistudio.google.com
||generativelanguage.googleapis.com

! Developer & CDN
||raw.githubusercontent.com
||objects.githubusercontent.com
||registry-1.docker.io
||production.cloudflare.docker.com

! Instant Messaging
||t.me
||telegram.org
EOF

# 2. 从 blackmatrix7 动态提取额外域名并追加进用户规则
# 注意：使用 || true 防止因网络问题导致 set -e 退出脚本
for url in \
  "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.list" \
  "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.list" \
  "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Telegram/Telegram.list"; do
  curl -sSL "$url" | grep -E '^(DOMAIN|DOMAIN-SUFFIX),' | awk -F',' '{print "||" $2}' >> "$USER_RULE_FILE" || true
done

# 3. 从 Loyalsoldier 提取代理列表
curl -sSL "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt" | grep -v '^#' | grep -v '^regexp:' | awk '{
    if ($0 ~ /^full:/) {
        sub(/^full:/, "");
        print "|http://" $0;
    } else if ($0 ~ /^domain:/) {
        sub(/^domain:/, "");
        print "||" $0;
    } else {
        print "||" $0;
    }
}' >> "$USER_RULE_FILE" || true

# 4. 执行 genpac 编译成最终的 PAC 文件
# 使用 jsdelivr 镜像源，因为 raw.githubusercontent.com 经常被墙返回 HTML 页面
genpac \
  --format=pac \
  --pac-proxy="$PAC" \
  --gfwlist-url="$GFWLIST_URL" \
  --user-rule-from="$USER_RULE_FILE" \
  -o "$WPAD"

echo "Info: PAC 文件已更新至: $WPAD"

# 5. 验证 PAC 文件规则
GOOGLE=$(pactester -p "$WPAD" -u https://www.google.com | tr -d '\r\n') || true
BAIDU=$(pactester -p "$WPAD" -u https://www.baidu.com | tr -d '\r\n') || true

echo "Info: 验证 PAC 文件规则..."
echo "  Google (https://www.google.com) 返回: [$GOOGLE]"
echo "  Baidu  (https://www.baidu.com)  返回: [$BAIDU]"
echo "  期望 Google 返回: [$PAC]"
echo "  期望 Baidu  返回: [DIRECT]"

if [ "$GOOGLE" != "$PAC" ] || [ "$BAIDU" != "DIRECT" ]; then
    echo "Error: $WPAD 文件规则验证失败！"
    echo "  Google 实际返回: [$GOOGLE] (期望: [$PAC])"
    echo "  Baidu 实际返回:  [$BAIDU] (期望: [DIRECT])"
    echo "Info: 正在恢复备份文件 $WPAD.bak ..."
    cp "$WPAD.bak" "$WPAD"
    exit 7
fi
echo "Info: $WPAD 生成并验证成功。"
