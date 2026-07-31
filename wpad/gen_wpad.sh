#!/bin/sh
# 脚本最后修改时间：2025.11.29 20:18
# set -x

# systemd service 实例的名称
# goproxy http 代理的端口(wpad 必须启用 http 代理)
HTTP_PORT=8888
# The SS_CFG file should be chmod 640, root:axu
SS_CFG="/etc/shadowsocks-libev/my_ss.json"

# 使用更可靠的 GFWList 镜像源 (jsdelivr CDN 或 GitLab)
GFWLIST_URL="https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt"
# 自定义用户规则文件 (如果存在则加载，用于添加特定的 PAC 规则)
USER_RULE_FILE="/etc/genpac/user-rules.txt"

# 额外可靠的代理规则源
URL_OPENAI="https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.list"
URL_CLAUDE="https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.list"
URL_TELEGRAM="https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Telegram/Telegram.list"
URL_LOYALSOLDIER="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"

# ##########################
chk_pkg() {
	# 检查必备的软件包
	# Check to install required packages
	PROG="shadowsocks-libev kcptun libpacparser1 haveged" # simple-obfs
	! echo $PROG | xargs dpkg-query -W >/dev/null && echo "Error: install $PROG first!" && exit 1
	# [ $? != 0 ] && sudo apt -y install $PROG
	! command -v genpac >/dev/null && echo "Error: install genpac by run # pip3 install genpac" && exit 1
	! command -v pactester >/dev/null && echo "Error: install libpacparser1 first." && exit 1
}

# ####
###########################

check_local_port() {
	nc -zv 127.0.0.1 $PRX_PORT
	[ $? != 0 ] && echo "Error: 请检查本地代理的服务端口：$PRX_PORT" && exit 1
}

check_wall() {
	CHECK_PROXY="127.0.0.1:$PRX_PORT"
	CHECK_URL="https://www.google.com/"
	check_local_port
	#
	echo "Info: 尝试科学上网 ..."
	echo "Running: curl -m 10 --socks5-hostname $CHECK_PROXY -kIsS $CHECK_URL"
	curl -m 10 --socks5-hostname "$CHECK_PROXY" -kIsS $CHECK_URL | grep -v "cookie"
	if [ $? != 0 ]; then
		echo "Error: 科学上网失败了"
	else
		echo "Info: 科学上网没问题"
	fi
}

# 下载并转换额外规则为 genpac 支持的 AdBlock Plus 格式
fetch_extra_rules() {
    TMP_RULES=$1
    echo "Info: 正在下载并解析额外的代理规则源..."
    
    # 1. blackmatrix7 规则 (OpenAI, Claude, Telegram)
    for url in "$URL_OPENAI" "$URL_CLAUDE" "$URL_TELEGRAM"; do
        curl -sSL "$url" | grep -E '^(DOMAIN|DOMAIN-SUFFIX),' | awk -F',' '{print "||"$2}' >> "$TMP_RULES"
    done

    # 2. Loyalsoldier 代理列表
    curl -sSL "$URL_LOYALSOLDIER" | grep -v '^#' | grep -v '^regexp:' | awk '{
        if ($0 ~ /^full:/) {
            sub(/^full:/, "");
            print "|http://" $0;
        } else if ($0 ~ /^domain:/) {
            sub(/^domain:/, "");
            print "||" $0;
        } else {
            print "||" $0;
        }
    }' >> "$TMP_RULES"
    
    # 3. 合并本地自定义规则
    if [ -r "$USER_RULE_FILE" ]; then
        echo "Info: 合并本地自定义规则 $USER_RULE_FILE"
        cat "$USER_RULE_FILE" >> "$TMP_RULES"
    fi
    
    # 去重并清理空行
    sort -u "$TMP_RULES" | sed '/^$/d' > "${TMP_RULES}.clean"
    mv "${TMP_RULES}.clean" "$TMP_RULES"
}

# Main Prog.
#
IFS=
# Host IP
chk_pkg
HIP=$(hostname -I | awk '{print $1}')
! nc -zv localhost 53  && echo "Error: local dns not up" && exit 2
HNAME="wpad.lan"
#
IP=$(dig -4 +short $HNAME @localhost)
if [ $? != 0 -o -z "$IP" ]; then
	echo "Error: $HNAME record was not setup correctly! "
	echo "Run: \"unbound-control local_data $HNAME. A $HIP\" to add $HNAME record and re-run this script."
	exit 1
fi
echo "$HNAME. was setup as $IP"
#
[ ! -r "$SS_CFG" ] && echo "Error: missing shadowsocks config file, $SS_CFG" && exit
PRX_PORT=$(cat $SS_CFG | jq -r ".local_port")
[ -z "$PRX_PORT" ] && echo "Error: Missing proxy port number" && exit 1
echo "Info: proxy port: $PRX_PORT"
PROXY="socks5 $IP:$PRX_PORT"

WPAD="/var/www/html/wpad/wpad.dat"
[ ! -w $WPAD ] && echo "Error: $WPAD file not writable!" && exit 2
# To let client use http://IP/wpad.dat to config auto proxy(Not all client/router comb support wpad name)
# [ ! -L /var/www/html/wpad.dat ] && sudo ln -s $WPAD /var/www/html
# use genpac to generate wpad.dat
# 
PAC="PROXY $IP:$HTTP_PORT; $PROXY"
check_local_port
echo "Info: generating $WPAD with --pac-proxy=\"$PAC\" ..."

# 备份现有的 wpad.dat (DO MAKE A BACKUP first)
cp $WPAD $WPAD.bak

# 准备临时规则文件
TMP_RULES_FILE=$(mktemp)
fetch_extra_rules "$TMP_RULES_FILE"

# 构建 genpac 命令参数
GENPAC_CMD="/usr/local/bin/genpac --format=pac --pac-proxy=\"$PAC\" --proxy \"socks5://127.0.0.1:$PRX_PORT\""
# 使用可靠的 GFWList 源
GENPAC_CMD="$GENPAC_CMD --gfwlist-url=\"$GFWLIST_URL\""
# 添加合并后的自定义及额外规则文件
GENPAC_CMD="$GENPAC_CMD --user-rule-from=\"$TMP_RULES_FILE\""

# 执行生成命令
eval $GENPAC_CMD | tee $WPAD >/dev/null
GENPAC_EXIT_CODE=$?

# 清理临时文件
rm -f "$TMP_RULES_FILE"

if [ $GENPAC_EXIT_CODE -ne 0 ]; then
    echo "Error: genpac 生成失败，正在恢复备份..."
    cp $WPAD.bak $WPAD
    exit 3
fi

# 验证 PAC 文件规则
# 使用 tr 去除可能的回车换行符，确保字符串比较准确
GOOGLE=$(pactester -p $WPAD -u https://www.google.com | tr -d '\r\n')
BAIDU=$(pactester -p $WPAD -u https://www.baidu.com | tr -d '\r\n')

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
    cp $WPAD.bak $WPAD
    exit 7
fi
echo "Info: $WPAD 生成并验证成功。"
