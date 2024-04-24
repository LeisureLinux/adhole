#!/bin/sh
# 检查本地解析和远端解析是否一致，如果不一致则清理本地 DNS 缓存
[ ! -x /usr/sbin/unbound-control ] && echo "Error: need to be able to exec: unbound-control" && exit 1
for d in "$@"; do
	L_IP=$(dig -tA +short "$d" @127.0.0.1)
	[ -z "$L_IP" ] && echo "Error in local resolving $d!" && exit 10
	G_IP=$(dig -tA +short "$d" @8.8.8.8)
	[ -z "$G_IP" ] && echo "Error in Google resolving $d!" && exit 11
	[ "$L_IP" != "$G_IP" ] && echo "\"$d\": Local: $L_IP; Google: $G_IP" && unbound-control flush "$d"
	echo "Sleeping 10 seconds ..."
	sleep 10
done
