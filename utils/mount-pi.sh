#!/bin/sh
# mount-pi.sh - 架构师专用的 Pi 镜像救砖与环境验证脚本
# Mount Arm SBC(Single Board Computer)
# Step 1: Use balena-Ether or silimar to burn downloaded image to microSD Card
# Step 2: fdisk to recreate partition 1, e2fsck and resize2fs to grow fs to actual microSD capacity(not neccesary can run systemd-resize-partion in OS)
# Step 3: Run this script.
DEV=$1
export LC_ALL=C
MOUNT_DIR="/mnt"
#
[ -z "$DEV" ] && echo "Syntax: $0 device_name" && exit
# Force mount device to /mnt
findmnt "${DEV}" >/dev/null && sudo umount -f "$DEV" && echo "Error: $DEV mounted, unmounted"
if ! sudo mount "$DEV" $MOUNT_DIR; then
  echo "Error: mount $DEV to $MOUNT_DIR failed!"
  exit 1
fi

[ ! -r $MOUNT_DIR/lib/systemd/systemd ] && echo "Error: $MOUNT_DIR/lib/systemd/systemd not exist." && exit 3
if [ $(readelf -h $MOUNT_DIR/lib/systemd/systemd | grep "Machine:" | awk '{print $2}') = "AArch64" ]; then
  qemu="/bin/qemu-aarch64-static"
else
  qemu="/bin/qemu-arm-static"
fi
[ ! -f /mnt/$qemu ] && sudo cp $qemu $MOUNT_DIR/usr/bin

# IMG_FILE=$1
# 
# if [[ -z "$IMG_FILE" ]]; then
#     echo "Usage: $0 <path_to_img_file>"
#     exit 1
# fi
# 
# # 1. 自动化挂载
# echo "[*] Preparing Loop device and mounting..."
# sudo mkdir -p $MOUNT_DIR
# # 自动寻找分区偏移并挂载 root 分区 (假设是第 2 分区)
# LOOP_DEV=$(sudo losetup -fP --show "$IMG_FILE")
# sudo mount "${LOOP_DEV}p2" $MOUNT_DIR

# 2. 后台启动 nspawn
# 使用你验证过的“万能组合参数”，确保不报 243 错误并顺利到达 multi-user.target
echo "[*] Spawning container in background..."
sudo systemd-nspawn -q -D $MOUNT_DIR -b \
    --private-users=no \
    --link-journal=no \
    --capability=all \
    --setenv=SYSTEMD_CREDENTIALS=0 \
    --setenv=SYSTEMD_SECCOMP=0 &

NSPAWN_PID=$!

# 3. 等待引导完成
echo "[*] Waiting for systemd to reach multi-user.target..."
# 循环检测容器是否已经在 machinectl 中注册
while ! sudo machinectl list | grep -q "mnt"; do
    sleep 1
done
# 额外等待 2 秒确保 login 准备就绪
sleep 2

# 4. 强制清理屏幕并进入 machinectl shell
clear
echo "--------------------------------------------------------"
echo "  Connected to $(basename $IMG_FILE) via machinectl"
echo "  Type 'exit' to quit and cleanup."
echo "--------------------------------------------------------"
sudo machinectl shell root@mnt /bin/bash

# 5. 退出后的清理逻辑
echo "[*] Exiting... Cleaning up resources."
# 优雅关闭容器
sudo machinectl terminate mnt
# 如果没关掉，强制杀掉进程
sudo kill $NSPAWN_PID 2>/dev/null

# 卸载并释放 Loop 设备
sudo umount -l $MOUNT_DIR
# sudo losetup -d $LOOP_DEV
# sudo rmdir $MOUNT_DIR

echo "[+] Done. System is clean."

exit

# 启动容器（后台保持运行，避开最核心的挂载坑）
sudo systemd-nspawn -q -D /mnt -b \
	--private-users=no \
    --private-network \
	--link-journal=no \
    --capability=all \
    --timezone=copy \
    --bind-ro=/etc/resolv.conf \
    --bind=/tmp/nspawn-var-log:/var/log \
    --bind=/tmp/fake_openclaw:/mnt/openclaw &

# 稍等 3 秒待引导完成，直接空降
sleep 3
sudo machinectl shell root@mnt
sudo killall systemd-nspawn || echo "Error: failed to kill systemd-nspawn"
sudo umount -f /mnt || echo "Error: failed to umount /mnt"
####

# modify repo to sjtu
# sudo sed -i -e 's/repo.huaweicloud.com/mirror.sjtu.edu.cn/g' /mnt/etc/apt/sources.list
#
# 在容器外执行，临时屏蔽掉容易出问题的服务
# sudo ln -sf /dev/null /mnt/etc/systemd/system/systemd-udev-load-credentials.service
# 
[ ! -d /tmp/fake_openclaw ] && sudo mkdir /tmp/fake_openclaw
mkdir -p /tmp/nspawn-var-log

sudo systemd-nspawn -D /mnt -b \
    --private-users=no \
	--console=interactive \
    --link-journal=no \
    --setenv=SYSTEMD_CREDENTIALS=0 \
    --setenv=SYSTEMD_SECCOMP=0 \
    --system-call-filter="@memlock @privileged @resources @mount" || echo "Error: 启动容器失败。"

    # --property="DeviceAllow=block-* rwm" \
    # --tmpfs=/run --tmpfs=/tmp --tmpfs=/var/run \
# --link-journal=try-guest \


#
# for d in /proc /sys /dev /dev/pts; do
#   [ ! -d /mnt"$d" ] && echo "Error: Not the right device? " && exit 2
#   sudo mount --bind $d /mnt$d
# done
# 
# [ ! -d /mnt/home/adhole ] && sudo git clone https://github.com/LeisureLinux/adhole.git /mnt/home/adhole
# if ! sudo chroot /mnt $qemu /bin/bash; then
#   echo "Error: chroot to /mnt failed!"
# fi
#
# After exit chroot. do umount
# for d in /proc /sys /dev/pts /dev; do
#   sudo umount /mnt$d
# done
# sudo umount /mnt
#
# What to do next:
usage() {

  echo "After chroot into Pi, do the followings:"
  echo "apt remove xfce4-\* thunar openvpn orca fping plymouth xscreensaver gtk2-engine-\* xwallpaper openvpn tightvncserver speech-dispatcher x11-apps iperf3  spice-vdagent fcitx-\* evince-\* geany-\* \
    gnome-\* gstreamer1.0-\* numix-\* orangepi-bsp-desktop-orangepizero3 orangepi-bullseye-desktop-xfce \
    dnsmasq xrdp brltty containerd.io xfce4 lightdm chromium vlc cups cups-bsd ghostscript cups-client xserver-common cups-common docker-ce docker-ce-cli "
  echo "# rm /etc/apt/sources.list.d/docker.list"
  echo "# apt autoremove"
  echo "# apt update && apt upgrade"
  echo "# dpkg-reconfigure locales"
  echo "# apt install neofetch nsd unbound systemd-timesyncd mieru-client vim psmisc curl python3 python3-pip nginx jq git netcat util-linux tree parallel avahi-daemon xz-utils lsof zstd libpython3.9 bind9-dnsutils network-manager dos2unix libpacparser1"
  echo "# useradd adhole -s /bin/bash -G sudo && passwd adhole"
  echo "# chown -R adhole /home/adhole"
  echo "# su - adhole"
  echo "# sed -i -e 's/MOTD_DISABLE=""/MOTD_DISABLE="header tips updates sysinfo config"/g' /etc/default/orangepi-motd"
  echo "# Remove the SD card, boot Pi, verify ssh: # ssh adhole@orangepizero3.local"
  echo "# setup_dns.sh && wpad/setup_wpad.sh && cd ss && cp two json config file from somewhere, run ./ss_install.sh"
  echo "# timedatectl set-timezone \"Asia/Shanghai\" "
  echo "# sed -i -e 's/^#NTP=/NTP=ntp.aliyun.com/g' /etc/systemd/timesyncd.conf"
  sleep 1
}
