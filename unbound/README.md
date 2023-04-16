# Enjoy the Ad-hassle-free world
  1. Purchase a raspberry Pi or similar SBC(Single Board Computer)
  2. Find a 16GB (suggested) SD-Card, burn with latest Debian/Ubuntu image(prefer 64-bit OS if your board support) 
  3. Upgrade your OS and packages to the latest version (run: sudo apt dist-upgrade) 
  4. Plugin your board into Wi-Fi router, bind your board MAC address to a static IP on your router's DHCP setting(preferred)
  5. After successfully setup the board according to below steps, point your Wi-Fi router's LAN DHCP config's DNS server to the boards's IP
 
# nsd+unbound install/setup steps
  1. Run ./install_pkg.sh to install the packages
  2. Run ./setup_dns.sh to setup the config files to enable/start DNS server
  3. Run ./wpad.sh if you want to make WPAD(Web Proxy Auto-Discovery) work in your LAN, which will need to add wpad record dynamically in DHCP environment

# Service and Ports
  - nsd service slave root zone from Internet, run on 127.0.0.1:1053
  - unbound service listen on 0.0.0.0:53 forward all to nsd, except those configured as local-zone
  
# Reminds
  - DNS is very tricky!
  - DNSSEC protocol is not enabled to avoid problems
  - We use nsd as root server to avoid DNS hijacking by ISP, normally root will tell us the correct NS record
  - On the board or the host itself, we use 127.0.0.1:53 e.g. unbound as local DNS resolver
