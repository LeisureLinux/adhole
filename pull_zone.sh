#!/bin/sh
# Run as root cron
# pull the latest adhole.conf from github
# Modify PROXY to your own
PROXY="--proxy socks5h://wpad.local:2023"
#
URL="https://raw.githubusercontent.com/LeisureLinux/adhole/main/data/adhole.conf.zst"
CONF_DIR="/etc/unbound/adhole"
CONF=$(basename $URL .zst)
echo "Info: downloading zone config file from github ..."
curl -sS $PROXY $URL -o /tmp/$CONF.zst
[ $? != 0 ] && echo "Error: Download $URL failed!" && exit 1
[ -r $CONF_DIR/$CONF ] && mv $CONF_DIR/$CONF $CONF_DIR/$CONF.bak
[ -d $CONF_DIR ] && echo "Info: Decompressing ..." && zst -ck \ 
-d /tmp/$CONF.zst >$CONF_DIR/$CONF && rm /tmp/$CONF.zst
[ -x /usr/sbin/unbound-control ] && echo "Info: reload unbound ..." && /usr/sbin/unbound-control reload
# touch a .wpad file in your env. to tell unbound add wpad record after zone reload
WORK_DIR=$(dirname $0)
[ -r $WORK_DIR/.wpad -a -x $WORK_DIR/wpad/wpad.sh ] && $WORK_DIR/wpad/wpad.sh
