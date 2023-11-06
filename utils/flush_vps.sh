#!/bin/sh
# 检查本地解析和远端解析是否一致，如果不一致则清理本地 DNS 缓存
DOMAIN="vps.freelamp.com."
L_IP=$(dig -4 +short $DOMAIN @127.0.0.1)
G_IP=$(dig -4 +short $DOMAIN @8.8.8.8)
[ -z "$L_IP" ] && echo "Error in local DNS resolve!" && exit 1
[ -z "$G_IP" ] && echo "Error in Google DNS resolve!" && exit 1
[ "$L_IP" != "$G_IP" ] && echo "Local: $L_IP; Google: $G_IP" && unbound-control flush $DOMAIN
