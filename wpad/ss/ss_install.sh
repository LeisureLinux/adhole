#!/bin/sh
# 一键安装 kcptun 以及 shadowsocks-libev 的客户端
# 加：nginx + wpad virtualhost config + genpac to generate wpad.dat + goproxy enable http_proxy
# 首先需要运行 $ ./dns_install.sh wpad，启用 wpad & wpad.local 记录，以便实现代理自动发现服务
# 要先准备好两个可以工作的 json 配置文件(包含密钥等敏感信息)
# 脚本接受两个参数： 1. wpad, 生成 wpad.dat 脚本； 2. deconfig: 停掉服务，删掉配置
# This will install service:
# 1. kcptun-local@$SVC_NAME
# 2. shadowsocks-libev-local@$SVC_NAME
# 3. goproxy.service
# Plus use genpac and gfwlist to build http://wpad/wpad.dat
# 脚本最后修改时间：2023.1.24 08:18
# set -x

# systemd service 实例的名称
SVC_NAME="my_ss"
# goproxy http 代理的端口(wpad 必须启用 http 代理)
HTTP_PORT=8888
#
# ##########################
chk_pkg() {
	# 检查必备的软件包
	# Check to install required packages
	PROG="shadowsocks-libev kcptun libpacparser1 haveged simple-obfs "
	sudo dpkg-query -W $PROG
	[ $? != 0 ] && sudo apt -y install $PROG
}

ss_cfg() {
	# 复制两个配置文件
	[ ! -r "$KCP_CFG" -o ! -r "$SS_CFG" ] && echo "Error: kcptun/ss config file not found!" && exit 1
	[ ! -d /etc/kcptun ] && sudo mkdir /etc/kcptun
	sudo cp -f $KCP_CFG /etc/kcptun/$SVC_NAME.json
	[ ! -d /etc/shadowsocks-libev ] && sudo mkdir /etc/shadowsocks-libev
	sudo cp -f $SS_CFG /etc/shadowsocks-libev/$SVC_NAME.json
	sudo chown root /etc/kcptun/$SVC_NAME.json /etc/shadowsocks-libev/$SVC_NAME.json
	sudo chmod 600 /etc/kcptun/$SVC_NAME.json /etc/shadowsocks-libev/$SVC_NAME.json
}

#
####
KCP_CFG="kcptun.json"
SS_CFG="ss.json"
[ -z "$1" ] && chk_pkg
[ -z "$1" ] && ss_cfg
PRX_PORT=$(cat $SS_CFG | jq -r ".local_port")
[ -z "$PRX_PORT" ] && echo "Error: Missing proxy port number" && exit 1
echo "Info: proxy port: $PRX_PORT"
###########################
# Functions
kcptun_svc() {
	[ -f /etc/systemd/system/kcptun-local@.service ] && return
	cat <<EOK | sudo tee /etc/systemd/system/kcptun-local@.service
#  This is a kcptun client 

[Unit]
Description= kcptun Client 
After=network.target

[Service]
Type=simple
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/kcptun-client -c /etc/kcptun/%i.json

[Install]
WantedBy=multi-user.target
EOK
}

ss_local_svc() {
	[ -f /etc/systemd/system/shadowsocks-libev-local@.service ] && return
	cat <<EOS | sudo tee /etc/systemd/system/shadowsocks-libev-local@.service
#  This file is part of shadowsocks-libev.
#
#  Shadowsocks-libev is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  This is a template unit file. Users may copy and rename the file into
#  config directories to make new service instances. See systemd.unit(5)
#  for details.

[Unit]
Description=Shadowsocks-Libev Custom Client Service for %I
Documentation=man:ss-local(1)
After=network.target

[Service]
Type=simple
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/ss-local -c /etc/shadowsocks-libev/%i.json

[Install]
WantedBy=multi-user.target
EOS
}

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

wpad_cfg() {
	[ -f /etc/nginx/conf.d/wpad.conf ] && return
	echo "Info: add Nginx wpad virtualhost config"
	cat <<EOW | sudo tee /etc/nginx/conf.d/wpad.conf
    server {
        listen 80;
        server_name "wpad" "wpad.local";
        root /var/www/html/wpad;

        access_log /var/log/nginx/wpad-access.log;
        error_log /var/log/nginx/wpad-error.log warn;
    }
EOW
}

install_goproxy() {
	# Install Goproxy to convert socks5 to http proxy
	[ -x "/usr/local/bin/goproxy" ] && return
	echo "Info: Checking github goproxy version ..."
	sudo git config --global http.proxy "socks5h://127.0.0.1:$PRX_PORT"
	VER=$(git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' https://github.com/snail007/goproxy.git | tail -1 | awk -F/ '{print $NF}')
	sudo git config --global http.proxy ''
	[ -z "$VER" ] && echo "Error: get goproxy version failed!" && exit 4
	echo "Info: Goproxy Version: [$VER]"
	# May modify in future to add more arch
	case "$(arch)" in
	"x86_64") ARCH="amd64" ;;
	"armv7l") ARCH="arm-v7" ;;
	"aarch64") ARCH="arm64-v8" ;;
	esac
	echo "Info: Downloading goproxy linux binary for arch=$ARCH from github ... "
	curl -m 10 -sSL -x socks5://127.0.0.1:$PRX_PORT https://github.com/snail007/goproxy/releases/download/$VER/proxy-linux-$ARCH.tar.gz -o /tmp/goproxy.tar.gz
	if [ $? = 0 ]; then
		echo "Info Downloaded goproxy $VER"
	else
		echo "Error: failed to download goproxy binary from github"
		exit 4
	fi
	sudo tar xzvf /tmp/goproxy.tar.gz -C /usr/local/bin proxy 2>/dev/null
	[ $? != 0 ] && echo "Error: install goproxy failed! Check file: /tmp/goproxy.tar.gz" && exit 4
	sudo rm /tmp/goproxy.tar.gz
	sudo mv /usr/local/bin/proxy /usr/local/bin/goproxy
	sudo chown root:root /usr/local/bin/goproxy
	sudo chmod 755 /usr/local/bin/goproxy
}

goproxy_cfg() {
	[ -f /etc/systemd/system/goproxy.service ] && return
	echo "Info: Config goproxy service ..."
	cat <<EOU | sudo tee /etc/systemd/system/goproxy.service
[Unit]
Description=goproxy 转换本地 socks 代理为 http 代理
After=syslog.target network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/goproxy sps --forever -S socks -T tcp -P 127.0.0.1:$PRX_PORT -t tcp -p :$HTTP_PORT
Restart= always
RestartSec=1min
ExecStop=/usr/bin/killall goproxy

[Install]
WantedBy=multi-user.target
EOU
	sudo systemctl daemon-reload
	sudo systemctl --now enable goproxy.service
	[ $? != 0 ] && echo "Error: config goproxy service failed!" && exit 9
	# # check http proxy working
	sleep 3
	nc -vz $IP ${HTTP_PORT}
	[ $? != 0 ] && echo "Error: setup http proxy on $IP:$HTTP_PORT failed!" && exit 10
}

gen_wpad() {
	WPAD="/var/www/html/wpad/wpad.dat"
	# To let client use http://IP/wpad.dat to config auto proxy(Not all client/router comb support wpad name)
	[ ! -L /var/www/html/wpad.dat ] && sudo ln -s $WPAD /var/www/html
	# use genpac to generate wpad.dat
	PAC="PROXY $IP:$HTTP_PORT; $PROXY"
	check_local_port
	echo "Info: generating $WPAD with --pac-proxy=\"$PAC\" ..."
	/usr/local/bin/genpac --format=pac --pac-proxy="$PAC" --gfwlist-proxy "socks5 127.0.0.1:$PRX_PORT" | sudo tee $WPAD >/dev/null
	GOOGLE=$(pactester -p $WPAD -u https://www.google.com)
	BAIDU=$(pactester -p $WPAD -u https://www.baidu.com)
	[ "$GOOGLE" != "$PAC" -o "$BAIDU" != "DIRECT" ] && echo "Error: Looked like $WPAD file not working correctly \
        Google return [$GOOGLE] should be [$PAC], Baidu should return [$BAIDU] " && exit 7
	echo "Info: $WPAD generated."
}

# deconfig ss/kcptun/goproxy, remove config files
deconfig() {
	sudo systemctl --now disable kcptun-local@${SVC_NAME}
	sudo systemctl --now disable shadowsocks-libev-local@${SVC_NAME}
	sudo rm -f /etc/kcptun/${SVC_NAME}.json
	sudo rm -f /etc/shadowsocks-libev/${SVC_NAME}.json
	# sudo rm /etc/systemd/system/shadowsocks-libev-local@.service /etc/systemd/system/kcptun-local@.service
	#
	sudo systemctl --now disable wpad.timer
	sudo systemctl --now disable wpad.service
	sudo rm /etc/systemd/system/wpad.timer /etc/systemd/system/wpad.service
	# deconfig nginx config
	sudo unlink /var/www/html/wpad.dat
	sudo rm /var/www/html/wpad/wpad.dat
	sudo rm /etc/nginx/conf.d/wpad.conf
	sudo nginx -s reload
	# remove goproxy service
	sudo systemctl --now disable goproxy
	sudo rm /etc/systemd/system/goproxy.service
	#
	sudo systemctl daemon-reload
	sudo systemctl reset-failed
	# sudo rm -f /usr/local/bin/goproxy
}

# Main Prog.
#
# deconfig
if [ "$1" = "deconfig" ]; then
	deconfig
	exit 0
fi
#
IFS=
HIP=$(hostname -I | awk '{print $1}')
IP1=$(dig -4 +short wpad.local @localhost | tail -1)
IP2=$(dig -4 +short wpad @localhost | tail -1)
if [ $? != 0 -o -z "$IP1" -o -z "$IP2" ]; then
	echo "Error: wpad record was not setup correctly! "
	echo "Run: \"unbound-control local_data wpad. A $HIP\" to add wpad record and re-run this script."
	exit 1
fi
IP=$IP1
echo "wpad.local was setup as $IP"
PROXY="socks5 $IP:$PRX_PORT"

# gen_wpad
if [ "$1" = "wpad" ]; then
	# wpad 内容需要根据 proxy IP 以及 gfwlist 内容动态调整，无法统一发布到板子上
	# 传递 wpad 参数时，仅仅更新 wpad 文件
	gen_wpad
	exit 0
fi

kcptun_svc
ss_local_svc

sudo systemctl daemon-reload
sudo systemctl --now disable shadowsocks-libev
sudo systemctl --now enable kcptun-local@${SVC_NAME}
sudo systemctl --now enable shadowsocks-libev-local@${SVC_NAME}
sleep 5
check_wall

install_goproxy
goproxy_cfg

#
# wpad Nginx part
[ ! -d /var/www/html/wpad ] && sudo mkdir -p /var/www/html/wpad
wpad_cfg
sudo nginx -t
[ $? != 0 ] && echo "Error: nginx web server config check failed!" && exit 3
sudo nginx -s reload
echo "ok" | sudo tee /var/www/html/wpad/ok.html
sleep 3
# Append wpad to /etc/hosts
echo "$IP wpad" | sudo tee -a /etc/hosts
# need to build a c-ares supported curl version
[ "$(curl -m 10 -sS http://wpad/ok.html)" != "ok" ] && echo "Error: double check nginx config failed." && exit 4
sudo rm /var/www/html/wpad/ok.html
# Remove last line
sudo sed -i '$ d' /etc/hosts
#
# Point pip to sjtu mirror
if [ -z "$(sudo pip3 config --user get global.index | grep sjtu)" ]; then
	sudo pip3 config --user set global.index https://mirror.sjtu.edu.cn/pypi-packages/
	sudo pip3 config --user set global.index-url https://mirror.sjtu.edu.cn/pypi/web/simple/
	sudo pip3 config --user set global.trusted-host mirror.sjtu.edu.cn
fi
[ ! -x "/usr/local/bin/genpac" ] && sudo pip3 install genpac --break-system-packages
#
gen_wpad

echo "Congrats! All is well."
