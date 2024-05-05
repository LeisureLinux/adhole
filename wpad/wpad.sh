#!/bin/sh
# wpad record in the LAN could be changed since its IP is obtained through DHCP
# placed this file as /etc/unbound/wpad.sh and will called as service
# Update wpad record, this need to to dynamically since IP could be changed
# Normally people will have only one device in home LAN as wpad web server
#
if [ "$(curl -q -4 -kIsS -w '%{json}\n' http://wpad/wpad.dat 2>/dev/null | tail -1 | jq -r .http_code)" != "200" ]; then
	echo "Error: Please setup wpad required web server first. e.g.: http://wpad/wpad.dat"
fi

NIC=$(ip -j -br r s default | jq -r '.[].dev')
# HIP4=$(hostname -I | awk '{print $1}')
# HIP6=$(hostname -I | awk '{print $2}')
HIP4=$(ip -4 -j -br add show "$NIC" | jq -r '.[].addr_info|.[].local')
HIP6=$(ip -6 -j add show "$NIC" scope global | jq -r '.[].addr_info|.[]|select (.temporary==null and .prefixlen==128).local')
[ -z "$HIP6" ] && HIP6=$(ip -6 -j add show "$NIC" scope global | jq -r '.[].addr_info|.[]|select (.temporary==null and .mngtmpaddr==null).local')
[ -z "$HIP6" ] && HIP6=$(ip -6 -j add show "$NIC" scope global | jq -r '.[].addr_info|.[]|select (.temporary==null and .dynamic==true).local')
if [ -n "$HIP4" ]; then
	CIP4="$(dig -4 -tA +short wpad. @localhost)"
	if [ "$CIP4" = "$HIP4" ]; then
		echo "Info: No need to update wpad. v4 record"
		RR4="local-data: \"wpad. 3600 IN A $CIP4\""
	else
		RR4="local-data: \"wpad. 3600 IN A $HIP4\""
		update=1
	fi
fi
if [ -n "$HIP6" ]; then
	# 	PREFIX=$(echo $HIP6 | cut -d: -f1,2)
	#	echo "$PREFIX"
	V6_ALLOW=$(ip -6 -j route show protocol ra dev "$NIC" | jq -r '.[]|select (.dst!="default" and .gateway==null).dst')
	[ -z "$V6_ALLOW" ] && V6_ALLOW=$(ip -6 -j route show protocol ra dev "$NIC" | jq -r '.[]|select (.dst!="default").dst')
	[ -z "$V6_ALLOW" ] && V6_ALLOW=$(ip -6 -j route show dev "$NIC" | jq -r '.[]|select (.dst!="default").dst' | grep -v "^fe80")
	# |startswith(PRE)')
	[ -n "$V6_ALLOW" ] && V6_ALLOW="access-control: $V6_ALLOW allow"
	CIP6="$(dig -tAAAA +short wpad. @localhost)"
	if [ "$CIP6" = "$HIP6" ]; then
		echo "Info: No need to update wpad. v6 record"
		RR6="local-data: \"wpad. 3600 IN AAAA $CIP6\""
	else
		RR6="local-data: \"wpad. 3600 IN AAAA $HIP6\""
		update=1
	fi
fi
echo "Info: v4 address: $HIP4; v6 address: $HIP6; v6 subnet to allow:$V6_ALLOW"
[ -z "$update" ] && echo "Info: old record is OK" && exit 1
WPAD="/etc/unbound/adhole/wpad.conf"
[ ! -f "$WPAD" ] && echo "Warning: No zone file $WPAD exist, no need to reload zone." && exit 9
[ ! -d /etc/unbound/adhole ] && mkdir -p /etc/unbound/adhole
echo "Updating wpad. v4+v6 record ..."
cat >$WPAD <<EOW
local-zone: "wpad." transparent
$RR4
$RR6
$V6_ALLOW
EOW
echo "Info: zone file:"
cat $WPAD
echo "Reloading zone config ..."
/usr/sbin/unbound-control reload && echo "All is well"
