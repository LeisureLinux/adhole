#!/bin/sh
# 脚本能力：
#  - 安装必备的工具： vim curl python3 python3-pip nginx jq shfmt netcat util-linux tree avahi-daemon
#  - 安装服务端 vim 写 shell以及配置 nginx 的必备插件 shfmt nginx-config
#  - 删除 nofound=return in /etc/nsswich.conf
#  - 配置 ntp 服务器为 ntp.aliyun.com
#  - 内网穿透能力

# 可能需要根据情况修改 PROXY 变量
# PROXY="-x socks5h://127.0.0.1:2023"
# 初始化 adhole 系统的版本
VER="1.1.2"
# Packages to install on Debian/Ubuntu systems
# gh=github-cli
PKGS="vim curl python3 python3-pip nginx jq git shfmt netcat util-linux \
    tree parallel avahi-daemon nsd unbound xz-utils zst libpython3.9 \
    bind9-dnsutils network-manager gh dos2unix"
# Modify to suit your own data
TZONE="Asia/Shanghai"
NTP="ntp.aliyun.com"
#
echo "Info: 本脚本需要 sudo 能力，检查当前用户是否具有 sudo 能力"
sudo -nv 2>/dev/null
[ $? != 0 ] && echo "Error: 当前用户没有 sudo 能力" && exit 1

ADHOLE="/etc/adhole_version"
[ "$(cat $ADHOLE 2>/dev/null)" != "$VER" ] && echo $VER | sudo tee $ADHOLE

update_issue() {
	# [ -r /etc/debian_version ] && DEB_VER=$(cat /etc/debian_version)
	cat <<EOI | sudo tee -a /etc/issue
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
	sudo dpkg-query -W $PKGS >/dev/null
	[ $? != 0 ] && sudo apt -y install $PKGS
	# 时钟管理非常重要，否则 DNS 不能工作(需要去和 root DNS 同步)
	# sudo apt -y purge ntp chrony 2>/dev/null
	sudo systemctl start systemd-timesyncd
	[ $? != 0 ] && echo "Error: Failed to start systemd-timesyncd" && exit 1
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
	# point nameserver to 127.0.0.1
	sudo mv -f /etc/resolv.conf /etc/resolv.conf.orig
	cat <<EOH | sudo tee /etc/resolv.conf
# Generated by adhole $VER
nameserver 127.0.0.1
EOH
	sudo systemctl enable NetworkManager
	sudo systemctl restart NetworkManager
	[ $? != 0 ] && echo "Error: Failed to start NetworkManager" && exit 1
	sudo apt -y autoremove
}

vim_plugInstall() {
	if [ ! -r ~/.vim/autoload/plug.vim ]; then
		# 下载安装 vim-plugin
		curl -fL -o ~/.vim/autoload/plug.vim --create-dirs \
			https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
	else
		# 检查安装的 Plugin
		local TMPFILE=/tmp/plugs.txt
		vim +"PlugStatus" +"write! $TMPFILE" +"qall"
		[ -n "$(grep "vim-shfmt: OK" $TMPFILE)" ] && echo "Info: 相关插件已经安装" && rm $TMPFILE && return
		rm $TMPFILE
	fi
	# 备份 .vimrc
	[ -r ~/.vimrc ] && mv ~/.vimrc ~/.vimrc.bak
	cat >~/.vimrc <<EOP
" Base vim plugin configuration
set number
call plug#begin('~/.vim/plugged')
  " shfmt the Shell formattor
  Plug 'z0mbix/vim-shfmt', { 'for': 'sh' }
  " nginx config
  Plug 'chr4/nginx'
call plug#end()
"
let g:shfmt_fmt_on_save = 1

EOP
	vim +"PlugInstall" +"qall"
}

# Main Prog.
update_issue
base_line
# If need vim plugins, enable vim_plugInstall
# vim_plugInstall
