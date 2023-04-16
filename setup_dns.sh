#!/bin/sh
# 请首先运行 install_pkg.sh ，确保系统打好基线，安装好必要的软件包
# Setup customized nsd + unbound daemon to provide a root zone transfer and recursive DNS resolver
# 使用 deconfig 参数，去掉配置
# Todo: add logrotate config
# set -x
#

echo "Info: 本脚本需要 sudo 能力，检查当前用户是否具有 sudo 能力"
sudo -nv 2>/dev/null
[ $? != 0 ] && echo "Error: 当前用户没有 sudo 能力" && exit 1

add_wpad() {
	# Add wpad record, this need to to dynamically since IP could be changed
	IFS=
	HIP=$(hostname -I | awk '{print $1}')
	[ -z "$HIP" ] && echo "Error: get IP address failed!" && exit 5
	echo "Info: Adding wpad. and wpad.local record ..."
	sudo unbound-control local_data wpad.local. A $HIP
	sudo unbound-control local_data wpad. A $HIP
	[ $? != 0 ] && echo "Error: not able to add wpad. record!" && exit 6
	[ "$(dig -4 +short wpad.local. @localhost)" != "$HIP" ] && echo "Error: added wpad not able to resolv!" && exit 7
	echo "Info: Adding wpad timer ..."
	sudo cp -f wpad/wpad.timer wpad/wpad.service /etc/systemd/system
	sudo systemctl daemon-reload
	sudo cp -f wpad/wpad.sh /etc/unbound
	sudo systemctl --now enable wpad.timer wpad.service
	[ $? != 0 ] && echo "Error: setup wpad timer failed!" && exit 8
	echo "Info: Added wpad. as $HIP"
}

deconfig() {
	# Disable service and remove config files only, not removing packages
	sudo systemctl --now disable unbound
	sudo systemctl --now disable nsd
	sudo systemctl status wpad.service 2>/dev/null
	if [ $? = 0 ]; then
		sudo systemctl --now disable wpad.service
		sudo systemctl --now disable wpad.timer
	fi
	sudo rm -f /etc/unbound/unbound.conf /etc/nsd/nsd.conf 2>/dev/null
}

# Main Prog.
[ "$1" = "deconfig" ] && deconfig && echo "Info: de-configured" && exit 0

# Required packages now should installted first through pre-config.sh
# PROG="nsd unbound libpython3.9 avahi-daemon"
#
[ -f /etc/adhole_version ] && VER=$(cat /etc/adhole_version)
[ -L /etc/resolv.conf ] && sudo unlink /etc/resolv.conf
[ -f /etc/resolv.conf ] && sudo cp /etc/resolv.conf /etc/resolv.conf.orig
echo "Info: generating /etc/resolv.conf ..."
cat <<EOH | sudo tee /etc/resolv.conf
# Generated by adhole $VER
nameserver 127.0.0.1
EOH
[ ! -f conf/nsd.conf -o ! -f conf/unbound.conf ] && echo "Error: existing unbound/nsd config not found" && exit 1
sudo mkdir -p /var/lib/unbound/logs 2>/dev/null
sudo mkdir -p /etc/unbound/adhole 2>/dev/null
sudo chown unbound /var/lib/unbound/logs
[ $? != 0 ] && echo "Error: there is issue in unbound installation" && exit 3
sudo cp -f conf/nsd.conf /etc/nsd
sudo cp -f conf/unbound.conf /etc/unbound
echo "Info: Enabling nsd and unbound service ..."
sudo systemctl enable nsd
sudo systemctl start nsd
[ $? != 0 ] && echo "Error: restart nsd service failed" && exit 2
sudo systemctl enable unbound
sudo systemctl start unbound
[ $? != 0 ] && echo "Error: restart unbound service failed" && exit 3
sleep 5
echo "Info: resolving www.baidu.com to validate dns server ..."
dig -4 +short www.baidu.com. @localhost
[ $? != 0 ] && echo "Error: not able to resolve www.baidu.com." && exit 4
[ "$1" = "wpad" ] && add_wpad
#
echo "Congrats, All is well!"