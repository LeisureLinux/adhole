#!/bin/sh
# wpad record in the LAN could be changed since its IP is obtained through DHCP
# placed this file as /etc/unbound/wpad.sh and will called as service
# Update wpad record, this need to to dynamically since IP could be changed
# Normally people will have only one device in home LAN as wpad web server
#

check_v4() {
	HIP4=$(ip -4 -j -br add show "$NIC" | jq -r '.[].addr_info|.[].local')
	echo "Info: v4 address: $HIP4"
	if [ -n "$HIP4" ]; then
		CIP4=$(dig -4 -t A +short wpad. @"$RESOLVER" 2>/dev/null)
		if [ "$CIP4" = "$HIP4" ]; then
			echo "Info: No need to update wpad. v4 record"
			RR4="local-data: \"wpad. 3600 IN A $CIP4\""
		else
			RR4="local-data: \"wpad. 3600 IN A $HIP4\""
			update=1
		fi
	fi
}

check_v6() {
	if [ "$(cat /sys/module/ipv6/parameters/disable)" = "1" ]; then
		echo "Error: IPv6 disabled in OS!"
		return
	fi
	# HIP6=$(hostname -I | awk '{print $2}')
	# 	HIP6=$(ip -6 -j add show "$NIC" scope global | jq -r '.[].addr_info|.[]|select (.temporary==null and .mngtmpaddr==null and .local!=null)|(.prefixlen,.local)' | paste - - | sort -n | tail -1 | awk '{print $NF}' | grep -i -E "^fc|^fd")
	HIP6=$(ip -6 -j add show "$NIC" | jq -r '.[].addr_info|.[]|select (.temporary==null and .mngtmpaddr==null and .local!=null)|(.prefixlen,.local)' | paste - - | awk '{print $NF}' | grep -i -E '^fc|^fd')
	# 	[ -z "$HIP6" ] && HIP6=$(ip -6 -j add show "$NIC" scope global | jq -r '.[].addr_info|.[]|select (.temporary==null and .dynamic==true).local')
	[ -z "$HIP6" ] && echo "Error: IPv6 not configured." && return
	if [ -n "$HIP6" ]; then
		echo "Info: v6 address: $HIP6"
		# 	PREFIX=$(echo $HIP6 | cut -d: -f1,2)
		#	echo "$PREFIX"
		V6_ALLOW=$(ip -6 -j route show protocol ra dev "$NIC" | jq -r '.[]|select (.dst!="default").dst' | grep -i -E '^fc|^fd')
		[ -z "$V6_ALLOW" ] && V6_ALLOW=$(ip -6 -j route show protocol ra dev "$NIC" | jq -r '.[]|select (.dst!="default" and .gateway==null).dst')
		[ -z "$V6_ALLOW" ] && V6_ALLOW=$(ip -6 -j route show dev "$NIC" | jq -r '.[]|select (.dst!="default").dst' | grep -v "^fe80")
		# |startswith(PRE)')
		echo "Info: v6 subnet to allow DNS query: $V6_ALLOW"
		[ -n "$V6_ALLOW" ] && V6_ALLOW=$(echo "$V6_ALLOW" | sort | uniq | awk '{print "access-control:",$0,"allow"}')
		CIP6=$(dig -t AAAA +short wpad. @"$RESOLVER" 2>/dev/null)
		if [ "$CIP6" = "$HIP6" ]; then
			echo "Info: No need to update wpad. v6 record"
			RR6="local-data: \"wpad. 3600 IN AAAA $CIP6\""
		else
			RR6="local-data: \"wpad. 3600 IN AAAA $HIP6\""
			update=1
		fi
	fi
}

# Main Prog.
RESOLVER=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | head -1)
[ -z "$RESOLVER" ] && RESOLVER="127.0.0.1"

if ! nc -4uvz "$RESOLVER" 53 2>/dev/null; then
	echo "Error: no DNS Service Running on $RESOLVER."
	exit 5
fi

NIC=$(ip -j -br r s default | jq -r '.[]|select (.protocol=="dhcp").dev')
[ -z "$NIC" ] && echo "Error: no default route found!" && exit 1
check_v4
check_v6
[ -z "$update" ] && echo "Info: old record is OK" && exit
WPAD="/etc/unbound/adhole/wpad.conf"
[ ! -f "$WPAD" ] && echo "Warning: No zone file $WPAD exists, no need to reload zone." && exit 9

if [ "$(curl -q -4 -kIsS -w '%{json}\n' http://wpad/wpad.dat 2>/dev/null | tail -1 | jq -r .http_code)" != "200" ]; then
	echo "Warning: Please setup wpad required web server first. e.g.: http://wpad/wpad.dat"
fi
#
[ ! -d /etc/unbound/adhole ] && sudo mkdir -p /etc/unbound/adhole
echo "Updating wpad. v4+v6 record ..."
cat >$WPAD <<EOW
local-zone: "wpad." transparent
$RR4
$RR6
$V6_ALLOW
EOW
echo "Info: zone file:"
cat $WPAD
if ! /usr/sbin/unbound-checkconf /etc/unbound/unbound.conf; then
	echo "Error: new config file $WPAD failed to pass check"
	exit 9
fi
echo "Reloading zone config ..."
/usr/sbin/unbound-control reload && echo "All is well"
