# Adhole
Adhole, a lightweight [pi-hole](https://github.com/pi-hole/pi-hole) without management ad-hocs, depends on [unbound](https://github.com/NLnetLabs/unbound) DNS Server 

# Enjoy the Ad-hassle-free world
  1. Purchase a raspberry Pi or similar SBC(Single Board Computer)
  2. Find a 16GB (suggested) SD-Card, burn with latest Debian/Ubuntu image(prefer 64-bit OS if your board support) 
  3. Upgrade your OS and packages to the latest version (run: sudo apt dist-upgrade) 
  4. Plugin your board into Wi-Fi router, bind your board MAC address to a static IP on your router's DHCP setting(preferred)
  5. After successfully setup the board according to below steps, point your Wi-Fi router's LAN DHCP config's DNS server to the board's IP

# Quick-start with qcow2 VM image if on a Linux machine(no need to run other steps)
  1. Download qcow2 image
     [here](https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole-01.qcow2.zst)
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
