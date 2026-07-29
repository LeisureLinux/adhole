#!/bin/sh
# mieru (client) 一键安装管理脚本
# 替代原来的 shadowsocks-libev + kcptun + gopropy 方案
#
# 用法:
#   ./install.sh          # 首次安装（自动安装软件包+配置+服务）
#   ./install.sh deconfig  # 卸载并清理配置
#   ./install.sh wpad      # 只更新 wpad.dat
#   ./install.sh status    # 查看 mieru 客户端状态
#
# set -x

# systemctl 服务实例名称
SVC_NAME="my_mieru"
# goproxy http 代理的端口(wpad 必须启用 http 代理)
HTTP_PORT=8888

# ##########################
# 检查必备的软件包
chk_pkg() {
	PROG="libpacparser1 haveged jq curl iproute2 nginx"
	sudo dpkg-query -W $PROG >/dev/null 2>&1 || {
		echo "Info: 安装基础依赖..."
		sudo apt -y update
		sudo apt -y install $PROG
	}
}

# 复制并应用 mieru 配置文件
apply_cfg() {
	[ ! -r "$MERA_CFG" ] && echo "Error: client config file not found!" && exit 1
	echo "Info: applying mieru configuration..."
	if ! sudo mieru apply config "$MERA_CFG"; then
		echo "Error: mieru apply config failed. Check your client.json!"
		exit 1
	fi
	echo "Info: check applied config:"
	mieru describe config
}

# 当前目录下的配置模板文件
MERA_CFG="client.json"
[ -z "$1" ] && chk_pkg
[ -z "$1" ] && apply_cfg

# 获取 http proxy 端口（从配置文件或默认值）
PRX_PORT=$(jq -r '.httpProxyPort // 8888' "$MERA_CFG")
[ -z "$PRX_PORT" ] && PRX_PORT=8888
echo "Info: http proxy port: $PRX_PORT"

check_local_port() {
	nc -zv 127.0.0.1 $PRX_PORT
	[ $? != 0 ] && echo "Error: 请检查本地代理服务端口：$PRX_PORT" && exit 1
}

check_wall() {
	CHECK_URL="https://www.google.com/"
	check_local_port
	echo "Info: 尝试科学上网 ..."
	echo "Running: curl --socks5-hostname 127.0.0.1:$PRX_PORT $CHECK_URL"
	curl -m 10 --proxy "http://127.0.0.1:$PRX_PORT" -kIsS $CHECK_URL | head -3
	if [ $? = 0 ]; then
		echo "Info: 科学上网 OK ✓"
	else
		echo "Error: 科学上网失败了 ✗"
		exit 1
	fi
}

# ========== MIERU systemd SERVICE ==========
create_systemd_service() {
	[ -f /etc/systemd/system/mieru@.service ] && return
	cat <<EOS | sudo tee /etc/systemd/system/mieru@.service
[Unit]
Description=Mieru Proxy Client (%i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mieru start
ExecStop=/usr/local/bin/mieru stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOS
	echo "Info: created /etc/systemd/system/mieru@.service"
}

# ========== GPORXY → MIERU HTTP PROXY ==========
# 不再需要 goproxy，mieru 内置了 socks5→http 转换
gopher_removed() {
	echo "Info: [skipped] goproxy removed - mieru built-in http proxy handles this."
}

gen_wpad() {
	WPAD="/var/www/html/wpad/wpad.dat"
	# 创建 wpad 软链接（如果还没有）
	[ ! -L /var/www/html/wpad.dat ] && sudo ln -sf $WPAD /var/www/html
	# use genpac to generate wpad.dat — 使用 miera 的 http proxy 端口
	PAC="PROXY $IP:$PRX_PORT; $PROXY"
	check_local_port
	echo "Info: generating $WPAD with PAC=$PAC ..."
	mkdir -p $(dirname $WPAD)
	/usr/local/bin/genpac --format=pac --pac-proxy="$PAC" --proxy "socks5://127.0.0.1:$PRX_PORT" | sudo tee $WPAD >/dev/null
	GOOGLE=$(pactester -p $WPAD -u https://www.google.com)
	BAIDU=$(pactester -p $WPAD -u https://www.baidu.com)
	[ "$GOOGLE" != "$PAC" -o "$BAIDU" != "DIRECT" ] && echo "Error: $WPAD validation failed. Google=$GOOGLE Baidu=$BAIDU" && exit 7
	echo "Info: $WPAD generated and validated ✓"
}

deconfig() {
	# 停止并禁用 mieru service
	sudo systemctl --now disable mieru@$SVC_NAME 2>/dev/null
	# 停止 mieru 客户端进程
	sudo mieru stop 2>/dev/null
	# 清理 wpad 相关
	sudo systemctl --now disable wpad.timer 2>/dev/null
	sudo systemctl --now disable wpad.service 2>/dev/null
	sudo rm -f /etc/systemd/system/wpad.timer /etc/systemd/system/wpad.service
	# 删除 nginx wpad 配置
	sudo unlink /var/www/html/wpad.dat 2>/dev/null
	sudo rm -f /var/www/html/wpad/wpad.dat
	sudo rm -f /etc/nginx/conf.d/wpad.conf 2>/dev/null
	sudo nginx -s reload 2>/dev/null
	sudo systemctl daemon-reload
	echo "Info: de-configured all mieru services."
}

# Main Prog.
#
[ "$1" = "deconfig" ] && deconfig && exit 0

IFS=
HIP=$(hostname -I | awk '{print $1}')
IP=$(dig -4 +short wpad @localhost 2>/dev/null | tail -1)
if [ -z "$IP" ]; then
	echo "Error: wpad DNS record not configured! Run setup_dns.sh first."
	exit 1
fi
echo "Info: wpad resolved to $IP"
PROXY="socks5 $IP:$PRX_PORT"

if [ "$1" = "wpad" ]; then
	gen_wpad
	exit 0
fi

# 创建系统服务
create_systemd_service
sudo systemctl daemon-reload

# 启动 mieru 客户端
echo "Info: Starting mieru client..."
sudo systemctl enable mieru@$SVC_NAME
sudo mieru start
sleep 3

# 验证连通性
check_wall

# 生成 wpad.dat
mkdir -p /var/www/html/wpad
if [ "$(curl -q -4 -kIsS -w '%{json}\n' http://wpad/wpad.dat 2>/dev/null | tail -1 | jq -r .http_code 2>/dev/null)" != "200" ]; then
	echo "Warning: WPAD web server not ready. Please ensure nginx is running."
else
	gen_wpad
fi

echo "Congrats! Mieru setup complete. ✓"
