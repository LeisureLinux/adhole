#!/bin/sh
# 请首先运行 install_pkg.sh ，确保系统打好基线，安装好必要的软件包
# 使用 deconfig 参数，去掉配置
# set -x
#
echo "Info: 本脚本需要 sudo 能力，检查当前用户是否具有 sudo 能力"
sudo -nv 2>/dev/null
[ $? != 0 ] && echo "Error: 当前用户没有 sudo 能力" && exit 1
#
cd $(dirname $0)

deconfig() {
	# Disable service and remove config files only, not removing packages
	cat /dev/null|sudo tee /etc/unbound/adhole/wpad.conf
		sudo systemctl --now disable wpad.service
		sudo systemctl --now disable wpad.timer
		sudo systemctl restart unbound
}

# Main Prog.
[ "$1" = "deconfig" ] && deconfig && echo "Info: de-configured" && exit 0
#
# Add wpad record, this need to to dynamically since IP could be changed
IFS=
HIP=$(hostname -I | awk '{print $1}')
[ -z "$HIP" ] && echo "Error: get IP address failed!" && exit 5
# check unbound service exist
# check nginx service started
# add wpad record
# curl http://wpad/wpad.dat OK
# pactester google.com through proxy(Not DIRECT)
sudo cp -f wpad.sh /etc/unbound
sudo /etc/unbound/wpad.sh -f
[ $? != 0 ] && echo "Error: run wpad.sh failed!" && exit 7
#
echo "Info: Adding wpad timer ..."
sudo cp -f wpad.timer wpad.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl --now enable wpad.timer wpad.service
[ $? != 0 ] && echo "Error: setup wpad timer failed!" && exit 8
echo "Info: Added wpad. as $HIP"
