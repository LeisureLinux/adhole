#!/bin/sh
# placed this file as /etc/unbound/wpad.sh and will called as service
# Update wpad record, this need to to dynamically since IP could be changed
# Normally people will have only one device in home LAN as wpad web server
# here put the deivce IP to provide wpad service(Todo: check http://wpad/wpad.dat OK)
HIP=$(hostname -I | awk '{print $1}')
[ "$(dig -4 +short wpad. @localhost)" = "$HIP" ] && echo "Info: No need to update wpad. record" && exit 1
[ ! -d /etc/unbound/adhole ] && mkdir -p /etc/unbound/adhole
echo "Updating wpad.local. record ..."
cat >/etc/unbound/adhole/wpad.conf <<EOW
local-zone: "wpad." transparent
local-zone: "wpad.local." transparent
local-data: "wpad. IN A $HIP"
local-data: "wpad.local. IN A $HIP"
EOW
/usr/sbin/unbound-control reload
