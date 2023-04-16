#!/bin/sh
# Run as root cron
# pull the latest adhole.conf from github
# Modify PROXY to your own
PROXY="--proxy socks5h://wpad.local:2023"
#
URL="https://raw.githubusercontent.com/LeisureLinux/adhole/main/data/adhole.conf.xz"
CONF_DIR="/etc/unbound/adhole"
CONF=$(basename $URL .xz)
curl -sS $PROXY $URL -o /tmp/$CONF.xz
[ $? != 0 ] && echo "Error: Download $URL failed!" && exit 1
[ -r $CONF_DIR/$CONF ] && mv $CONF_DIR/$CONF $CONF_DIR/$CONF.bak
[ -d $CONF_DIR ] && echo "Info: Decompressing ..." && xzcat /tmp/$CONF.xz >$CONF_DIR/$CONF
[ -x /usr/sbin/unbound-control ] && /usr/sbin/unbound-control reload
# touch a .wpad file in your env. to tell unbound add wpad record after zone reload
WORK_DIR=$(dirname $0)
[ -r $WORK_DIR/.wpad -a -x $WORK_DIR/wpad/wpad.sh ] && $WORK_DIR/wpad/wpad.sh
