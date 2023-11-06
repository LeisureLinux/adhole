#!/bin/sh
# 检查本地解析和远端解析是否一致，如果不一致则清理本地 DNS 缓存
[ ! -x /usr/sbin/unbound-control ] && echo "Error: need to be able to exec: unbound-control" && exit 1
for d in "$@"; do
    L_IP=$(dig -4 +short "$d" @127.0.0.1)
    G_IP=$(dig -4 +short "$d" @8.8.8.8)
    [ -z "$L_IP" ] && echo "Error in local DNS resolve!" && exit 10
    [ -z "$G_IP" ] && echo "Error in Google DNS resolve!" && exit 11
    [ "$L_IP" != "$G_IP" ] && echo "\"$d\": Local: $L_IP; Google: $G_IP" && unbound-control flush "$d"
done
