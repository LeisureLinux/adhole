#!/bin/sh
# Mount New OrangePi after burned xfce4 debian bullseye image
# Step 1: Use Ether or silimar to burn downloaded image to microSD Card
# Step 2: fdisk to recreate partition 1, e2fsck and resize2fs to grow fs to actual microSD capacity
# Step 3: Run this script.
DEV=$1
[ -z "$DEV" ] && echo "Syntax: $0 device" && exit
findmnt "${DEV}" >/dev/null && sudo umount -f "$DEV" && echo "Error: $DEV mounted, unmounted"
sudo mount "$DEV" /mnt
for d in /proc /sys /dev /dev/pts; do
	sudo mount --bind $d /mnt$d
done
[ ! -f /mnt/bin/qemu-arm64-static ] && sudo cp /bin/qemu-arm64-static /mnt/bin
# modify repo to sjtu
sudo sed -i -e 's/repo.huaweicloud.com/mirror.sjtu.edu.cn/g' /mnt/etc/apt/sources.list
[ ! -d /mnt/home/adhole ] && sudo git clone https://github.com/LeisureLinux/adhole.git /mnt/home/adhole
# What to do next:
echo "After chroot into Pi, do the followings:"
echo "apt remove xfce4-\* thunar openvpn orca fping plymouth xscreensaver gtk2-engine-\* xwallpaper openvpn tightvncserver speech-dispatcher x11-apps iperf3  spice-vdagent fcitx-\* evince-\* geany-\* \
    gnome-\* gstreamer1.0-\* numix-\* orangepi-bsp-desktop-orangepizero3 orangepi-bullseye-desktop-xfce \
    dnsmasq xrdp brltty containerd.io xfce4 lightdm chromium vlc cups cups-bsd ghostscript cups-client xserver-common cups-common docker-ce docker-ce-cli "
echo "# rm /etc/apt/sources.list.d/docker.list"
echo "# apt autoremove"
echo "# apt update && apt upgrade"
echo "# dpkg-reconfigure locales"
echo "# apt install neofetch nsd unbound systemd-timesyncd shadowsocks-libev kcptun vim psmisc curl python3 python3-pip nginx jq git netcat util-linux tree parallel avahi-daemon xz-utils lsof zstd libpython3.9 bind9-dnsutils network-manager dos2unix libpacparser1"
echo "# useradd adhole -s /bin/bash -G sudo && passwd adhole"
echo "# chown -R adhole /home/adhole"
echo "# su - adhole"
echo "# sed -i -e 's/MOTD_DISABLE=""/MOTD_DISABLE="header tips updates sysinfo config"/g' /etc/default/orangepi-motd"
echo "# Remove the SD card, boot Pi, verify ssh: # ssh adhole@orangepizero3.local"
echo "# setup_dns.sh && wpad/setup_wpad.sh && cd ss && cp two json config file from somewhere, run ./ss_install.sh"
echo "# timedatectl set-timezone \"Asia/Shanghai\" "
echo "# sed -i -e 's/^#NTP=/NTP=ntp.aliyun.com/g' /etc/systemd/timesyncd.conf"
sleep 1
# chroot
sudo chroot /mnt qemu-arm64-static /bin/bash
#
# After exit chroot. do umount
for d in /proc /sys /dev/pts /dev; do
	sudo umount /mnt$d
done
sudo umount /mnt
#
