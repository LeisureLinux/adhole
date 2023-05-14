# Adhole
Adhole, a lightweight [pi-hole](https://github.com/pi-hole/pi-hole) without management ad-hocs, depends on [unbound](https://github.com/NLnetLabs/unbound) DNS Server 

# Enjoy the Ad-hassle-free world
  1. Purchase a raspberry Pi or similar SBC(Single Board Computer)
  2. Find a 16GB (suggested) SD-Card, burn with latest Debian/Ubuntu image(prefer 64-bit OS if your board support) 
  3. Upgrade your OS and packages to the latest version (run: sudo apt dist-upgrade) 
  4. Plugin your board into Wi-Fi router, bind your board MAC address to a static IP on your router's DHCP setting(preferred)
  5. After successfully setup the board according to below steps, point your Wi-Fi router's LAN DHCP config's DNS server to the board's IP
 
# Windows 上使用 VirtualBox 挂接 vdi 虚机镜像，测试效果
  1. [下载镜像](https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole-18.vdi.zip)
  2. 解压，如果有移动需求，可以把解压后的 .vdi 文件复制到 U盘
  3. 安装好 VirtualBox ，以及 Extension Pack
  4. VirtualBox 界面下按 Ctr-D ，选择注册，把解压后的 .vdi (复制到 U盘上的需要用 U盘的路径)注册到系统
  5. 新建一个虚机，名字随便取，操作系统选择 Linux/Debian11 64bit，网络必须选择“桥接”模式（默认为 NAT），内存选 1024M，处理器设置为 1 即可。
  6. 虚拟机操作系统的主机名为 adhole-18，登录用户名为 adhole，在开启了
     avahi-daemon 的 Linux 机器， 或者 macOS 上可以直接在命令行用 ssh
     adhole@adhole-18.local 登录系统，密码是短的主机名。
  7. 登录后，可以 sudo -s 成为超级用户， git clone；cd /root/adhole，运行 ./pull_zone.sh 拉取最新的 zone 文件
  8. 如果已经有内网代理的话， echo "http://proxy-ip:port/" > /root/adhole/.proxy 
  9. 验证：把 Windows 机器或者家里无线路由器的 DNS 地址，设置为这台虚机的 IP 地址，看是否能解析 www.baidu.com
      ```
       具体步骤：
       - 打开 Windows  cmd 命令
       - 输入 nslookup
       - 输入 server 192.168.100.102 (这里假定这个 IP 是虚拟机的IP)
       - 输入 www.baidu.com (应该返回正常的 baidu.com 的 IP 地址)
       - 输入 a.baidu.com （应该返回 0.0.0.0，表明 adhole 已经生效）
       - exit
      ```
  10. 如何不通过 console 登录就能查看到虚拟机的 IP 地址？
        - Windows 主机上运行 arp -a 命令，查看虚机网卡 mac 地址下对应的 IP 地址
        - 登录到无线路由器上，去查看 DHCP 客户端的地址
        - 在 Windows 主机上安装 Advanced IP Scanner 程序，扫描本机网段
  11. 又：实际上不设置为 Bridge 也是可以的，如果是 NAT 模式，无非就是再添加端口转发，把 UDP 53 端口，转发到虚机的 UDP 53 端口
      
 
# Quick-start with qcow2 VM image if on a Linux machine(no need to run other steps)
  1. Download qcow2 image
     [here](https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole-1.1.5_amd64.qcow2.zst)
  2. Decompress with: zstd -d adhole-01.qcow2.zst 
  3. Import qcow2 image:
     ```
       virt-install --vcpu 1 --memory 2048 --name your_VM_name \
        --osinfo detect=on,name=generic --network your_networkname \
        --noautoconsole --import --disk your_path_to_adhole-01.qcow2 \
        --cloud-init clouduser-ssh-key=your_ssh_pubkey
     ```
  4. Debug import process:
     ```
       # Check console output, try login with root/LeisureLinux
       virsh console your_VM_name
       # Check VM's IP address
       virsh net-dhcp-leases default
     ```
  5. Check account "debian":
     ```
      ssh debian@IP_Address 
      # if your host running avahi-daemon, just use
      ssh debian@adhole-01.local
      # if want to assign your own password(password login disabled by default)
      sudo -s
      passwd debian
     ```
  6. Network port check
     ```
      # check port 53 and port 1053 is up
      ss -tln 
      # will return IP address of www.baidu.com
      dig +short -4 www.baidu.com @localhost
     ```
  7. Appendix: How to generate/publish qcow2?
     ```
      rm ~debian/.ssh/*
      passwd root (assign a password you can share to world)
      apt clean && apt autoclean
      rm /var/log/*.log
      cloud-init clean
     ```
     
# nsd+unbound install/setup steps(as root on a bare debian OS)
  1. Run ./install_pkg.sh to install the packages
  2. Run ./setup_dns.sh to setup the config files to enable/start DNS server
  3. Add ./pull_zone.sh to root crontab to pull adhole.conf daily from github and reload zone

# Service and Ports
  - nsd service slave root zone from Internet, run on 127.0.0.1:1053
  - unbound service listen on 0.0.0.0:53 forward all to nsd, except those configured as local-zone
 
# WPAD (Web Proxy Auto-Discovery)
  - run setup_wpad.sh to add the wpad.service and wpad.timer to check wpad
    record every 10 min.
  - Why WPAD: if you have multiple devices in home, and switch on/off VPN is
    tedius, just setup the device network setting's proxy as auto, the auto proxy URL is
    http://wpad.local/wpad.dat in case you need to add it manully(On iOS this is not needed)
  
# Zone config data
  - Contribute your own unblock_domains.txt and block_domains.txt, Request PR.
  - Run [adhole.sh](data/adhole.sh) to generate the adhole.conf adblock zone config
  
# Reminds
  - DNS is very tricky!
  - DNSSEC protocol is not enabled to avoid problems
  - We use nsd as root server to avoid DNS hijacking by ISP, normally root will tell us the correct NS record
  - On the board or the host itself, we use 127.0.0.1:53 e.g. unbound as local DNS resolver

# Pull zone config from github
  - Write a daily cron is a piece of cake, before add to cron, run it manually as root first in terminal
  ```
    crontab -e
    # run at 2:10 AM everyday
    10 2 * * * $your_dir/pull_zone.sh 1>/dev/null
  ```
