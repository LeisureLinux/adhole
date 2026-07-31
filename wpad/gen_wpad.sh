#!/bin/sh
# 脚本最后修改时间：2025.11.29 20:18
# set -x

# systemd service 实例的名称
# goproxy http 代理的端口(wpad 必须启用 http 代理)
HTTP_PORT=8888
# The SS_CFG file should be chmod 640, root:axu
SS_CFG="/etc/shadowsocks-libev/my_ss.json"
#
# ##########################
chk_pkg() {
	# 检查必备的软件包
	# Check to install required packages
	PROG="shadowsocks-libev kcptun libpacparser1 haveged" # simple-obfs
	! echo $PROGS|xargs dpkg-query -W >/dev/null && echo "Error: install $PROG first!" && exit 1
	# [ $? != 0 ] && sudo apt -y install $PROG
	! command -v genpac >/dev/null && echo "Error: install genpac by run # pip3 install genpac" && exit 1
	! command -v pactester >/dev/null && echo "Error: install libpacparser1 first." && exit 1
}

#
####
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

# Main Prog.
#
IFS=
# Host IP
chk_pkg
HIP=$(hostname -I | awk '{print $1}')
! nc -zvu localhost 53  && echo "Error: local dns not up" && exit 2
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
cp $WPAD $WPAD.bak
/usr/local/bin/genpac --format=pac --pac-proxy="$PAC" --proxy "socks5://127.0.0.1:$PRX_PORT" | tee $WPAD >/dev/null
GOOGLE=$(pactester -p $WPAD -u https://www.google.com)
BAIDU=$(pactester -p $WPAD -u https://www.baidu.com)
[ "$GOOGLE" != "$PAC" -o "$BAIDU" != "DIRECT" ] && echo "Error: Looked like $WPAD file not working correctly \
        Google return [$GOOGLE] should be [$PAC], Baidu should return [$BAIDU] " && cp $WPAD.bak $WPAD && exit 7
echo "Info: $WPAD generated."
