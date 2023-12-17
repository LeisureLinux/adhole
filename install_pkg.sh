#!/bin/sh
# 脚本能力：
#  - 安装必备的工具： vim curl python3 python3-pip nginx jq shfmt netcat util-linux tree avahi-daemon
#  - 删除 nofound=return in /etc/nsswich.conf
#  - 配置 ntp 服务器为 ntp.aliyun.com

# 可能需要根据情况修改 PROXY 变量
# PROXY="-x socks5h://127.0.0.1:2023"
# 初始化 adhole 系统的版本
VER="1.1.6"
# Packages to install on Debian/Ubuntu systems
# gh=github-cli
# added libpacparser1 to check wpad proxy setup
PKGS="vim psmisc curl python3 python3-pip nginx jq git netcat-openbsd util-linux \
    tree parallel avahi-daemon nsd unbound xz-utils lsof zstd \
    bind9-dnsutils network-manager dos2unix libpacparser1 systemd-timesyncd"
# Modify to suit your own requirement if not in China.
TZONE="Asia/Shanghai"
NTP="ntp.aliyun.com"
#
echo "Info: 本脚本需要 sudo 能力，检查当前用户是否具有 sudo 能力"
if ! sudo -nv 2>/dev/null; then
	echo "Error: 当前用户没有 sudo 能力"
	exit 1
fi

ADHOLE="/etc/adhole_version"
[ "$(cat $ADHOLE 2>/dev/null)" != "$VER" ] && echo $VER | sudo tee $ADHOLE

update_issue() {
	# [ -r /etc/debian_version ] && DEB_VER=$(cat /etc/debian_version)
	[ -r /etc/issue ] && sudo mv /etc/issue /etc/issue.orig
	cat <<EOI | sudo tee /etc/issue
adhole $VER \S \l
EOI
	if [ ! -x /etc/update-motd.d/09-issue ]; then
		cat <<EOSS | sudo tee /etc/update-motd.d/09-issue
#!/bin/sh
[ -x /sbin/agetty -a -r /etc/issue ] && /sbin/agetty --show-issue
EOSS
		sudo chmod +x /etc/update-motd.d/09-issue
	fi
	sudo run-parts --lsbsysinit /etc/update-motd.d | sudo tee /run/motd.dynamic
}

base_line() {
	# 基线，使用 network-manager，停用 systemd-resolved
	# sudo dpkg-query -W $PKGS >/dev/null
	if ! sudo -E apt -y install ${PKGS}; then
		echo "Error: Install PKGs failed!"
		exit 1
	fi
	# 时钟管理非常重要，否则 DNS 不能工作(需要去和 root DNS 同步)
	# sudo apt -y purge ntp chrony 2>/dev/null
	if ! sudo systemctl start systemd-timesyncd; then
		echo "Error: Failed to start systemd-timesyncd"
		exit 1
	fi
	sudo timedatectl set-timezone "$TZONE"
	sudo sed -i "s/#NTP=/NTP=$NTP/g" /etc/systemd/timesyncd.conf
	sudo systemctl restart systemd-timesyncd
	[ "$(sudo timedatectl show-timesync | awk -F= '$1 == "SystemNTPServers" {print $2}')" != "$NTP" ] && echo "Error: setup systemd-timesyncd ntp server to ntp.aliyun.com failed!" && exit 1
	sudo systemctl --now enable systemd-timesyncd
	# NetworkManager
	echo "Info: modify /etc/NetworkManager/NetworkManager.conf ..."
	sudo systemctl --now disable systemd-resolved 2>/dev/null
	sudo cp -f /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf.orig
	if [ -n "$(grep '^rc-manager=' /etc/NetworkManager/NetworkManager.conf)" ]; then
		sudo sed -i 's/^rc-manager=.*/rc-manager=unmanaged/g' /etc/NetworkManager/NetworkManager.conf
	else
		sudo sed -i '/^\[main/a rc-manager=unmanaged' /etc/NetworkManager/NetworkManager.conf
	fi
	if [ -n "$(grep '^dns=' /etc/NetworkManager/NetworkManager.conf)" ]; then
		sudo sed -i 's/^dns=.*/dns=none/g' /etc/NetworkManager/NetworkManager.conf
	else
		sudo sed -i '/^\[main/a dns=none' /etc/NetworkManager/NetworkManager.conf
	fi
	# Point nameserver to 127.0.0.1
	sudo mv -f /etc/resolv.conf /etc/resolv.conf.orig
	# Todo: add default router as nameserver
	cat <<EOH | sudo tee /etc/resolv.conf
# Generated by adhole $VER
nameserver 127.0.0.1
EOH
	sudo systemctl --now disable ModemManager 2>/dev/null
	sudo systemctl --now disable wpa_supplicant 2>/dev/null
	sudo systemctl --now disable nsd 2>/dev/null
	sudo systemctl --now disable unbound 2>/dev/null
	sudo systemctl enable NetworkManager
	if ! sudo systemctl restart NetworkManager; then
		echo "Error: Failed to start NetworkManager"
		exit 1
	fi
	sudo apt -y autoremove
}

# Main Prog.
update_issue
base_line
