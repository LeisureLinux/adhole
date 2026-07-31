#!/usr/bin/env bash
set -euo pipefail

# goproxy http 代理的端口(wpad 必须启用 http 代理)
HTTP_PORT=8888
# SOCKS5 代理端口 (请根据实际使用的代理软件修改)
PRX_PORT=1080

WPAD="/var/www/html/wpad/wpad.dat"
USER_RULE_FILE="/tmp/custom-user-rules.txt"

# 使用可靠的 GFWList 镜像源 (避免 raw.githubusercontent.com 被墙导致下载到 HTML 页面)
GFWLIST_URL="https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt"

# ##########################
usage() {
    cat <<EOF
用法: $0 [选项]

选项:
  -g, --generate    生成并更新 PAC 文件，然后进行验证
  -t, --test        仅验证现有的 PAC 文件规则
  -h, --help        显示此帮助信息

示例:
  $0 -g             # 生成新的 wpad.dat
  $0 -t             # 测试当前的 wpad.dat
EOF
}

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

get_network_info() {
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

    echo "Info: proxy port: $PRX_PORT"
    PROXY="socks5 $IP:$PRX_PORT"
    PAC="PROXY $IP:$HTTP_PORT; $PROXY"
}

fetch_rules() {
    echo "Info: 正在获取并合并代理规则..."
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
    
    # 4. 下载 GFWList 并解码，与用户规则合并以实现全局去重
    echo "Info: 正在下载并解码 GFWList..."
    GFWLIST_LOCAL="/tmp/gfwlist_decoded.txt"
    curl -sSL "$GFWLIST_URL" | base64 -d > "$GFWLIST_LOCAL" || true
    
    # 将 GFWList 追加到用户规则文件中
    cat "$GFWLIST_LOCAL" >> "$USER_RULE_FILE"
    rm -f "$GFWLIST_LOCAL"

    # 5. 规则全局去重与清理
    echo "Info: 正在清理注释、空行并对所有规则进行全局去重..."
    # 过滤掉 AdBlock Plus 格式的注释(!)、空白行、以及 GFWList 的头([AutoProxy...)
    grep -v '^!' "$USER_RULE_FILE" | grep -v '^[[:space:]]*$' | grep -v '^\[' | sort -u > "${USER_RULE_FILE}.tmp"
    mv "${USER_RULE_FILE}.tmp" "$USER_RULE_FILE"

    echo "Info: 规则合并并去重完成，临时文件: $USER_RULE_FILE"
}

generate_pac() {
    check_local_port
    echo "Info: generating $WPAD with --pac-proxy=\"$PAC\" ..."

    # 备份现有的 wpad.dat
    if [ -f "$WPAD" ]; then
        cp "$WPAD" "$WPAD.bak"
    fi

    fetch_rules

    # 执行 genpac 编译成最终的 PAC 文件
    # 使用本地合并并去重后的规则文件，避免 genpac 内部合并多源规则时产生重复
    genpac \
      --format=pac \
      --pac-proxy="$PAC" \
      --gfwlist-local="$USER_RULE_FILE" \
      -o "$WPAD"

    # 清理临时规则文件
    rm -f "$USER_RULE_FILE"

    echo "Info: PAC 文件已更新至: $WPAD"
}

test_pac() {
    if [ ! -r "$WPAD" ]; then
        echo "Error: $WPAD 文件不存在或不可读，无法进行测试。"
        exit 1
    fi

    GOOGLE=$(pactester -p "$WPAD" -u https://www.google.com | tr -d '\r\n') || true
    BAIDU=$(pactester -p "$WPAD" -u https://www.baidu.com | tr -d '\r\n') || true
    OPENAI=$(pactester -p "$WPAD" -u https://chatgpt.com | tr -d '\r\n') || true

    echo "Info: 验证 PAC 文件规则..."
    echo "  Google (https://www.google.com) 返回: [$GOOGLE]"
    echo "  Baidu  (https://www.baidu.com)  返回: [$BAIDU]"
    echo "  OpenAI (https://chatgpt.com)    返回: [$OPENAI]"
    echo "  期望 Google 返回: [$PAC]"
    echo "  期望 Baidu  返回: [DIRECT]"
    echo "  期望 OpenAI 返回: [$PAC]"

    if [ "$GOOGLE" != "$PAC" ] || [ "$BAIDU" != "DIRECT" ] || [ "$OPENAI" != "$PAC" ]; then
        echo "Error: $WPAD 文件规则验证失败！"
        echo "  Google 实际返回: [$GOOGLE] (期望: [$PAC])"
        echo "  Baidu 实际返回:  [$BAIDU] (期望: [DIRECT])"
        echo "  OpenAI 实际返回: [$OPENAI] (期望: [$PAC])"
        return 1
    fi
    echo "Info: $WPAD 验证成功。"
    return 0
}

# ##########################
# Main Prog.
# ##########################

# 没有参数时显示帮助
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

case "$1" in
    -t|--test)
        echo "Info: 仅执行 PAC 文件测试模式..."
        chk_pkg
        get_network_info
        if test_pac; then
            exit 0
        else
            exit 7
        fi
        ;;
    -g|--generate)
        chk_pkg
        get_network_info
        
        # 检查目标目录和文件权限
        DIR=$(dirname "$WPAD")
        if [ ! -d "$DIR" ]; then
            mkdir -p "$DIR" || { echo "Error: Cannot create directory $DIR"; exit 2; }
        elif [ ! -w "$DIR" ]; then
            echo "Error: Directory $DIR is not writable!"
            exit 2
        fi
        if [ -f "$WPAD" ] && [ ! -w "$WPAD" ]; then
            echo "Error: $WPAD file not writable!"
            exit 2
        fi

        generate_pac
        if ! test_pac; then
            echo "Info: 正在恢复备份文件 $WPAD.bak ..."
            cp "$WPAD.bak" "$WPAD"
            exit 7
        fi
        echo "Info: $WPAD 生成并验证成功。"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Error: 未知参数 '$1'"
        usage
        exit 1
        ;;
esac
