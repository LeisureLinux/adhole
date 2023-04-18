#!/bin/bash
# Run as root cron
# pull the latest adhole.conf.zst from github
# put your proxy server e.g. http://IP:port or socks5://IP:port to .proxy
# touch a .wpad file in your env. to tell unbound add wpad record after zone reload
WORK_DIR=$(dirname $0)
PFILE="$WORK_DIR/.proxy"
[ -r "$PFILE" ] && PROXY="--proxy $(cat $PFILE)"
[ ! -x /usr/bin/zst ] && echo "Error: Please install zst package" && exit
#
URL="https://raw.githubusercontent.com/LeisureLinux/adhole/main/data/adhole.conf.zst"
#
CONF_DIR="/etc/unbound/adhole"
CONF=$(basename $URL .zst)
if [ ! -r $CONF_DIR/$CONF -o "$(find $CONF_DIR/$CONF -mtime +1)" ]; then
	echo "Info: downloading zone config $CONF.zst file from github ..."
	curl -sS $PROXY $URL -o /tmp/$CONF.zst
	[ $? != 0 ] && echo "Error: Download $URL failed!" && exit 1
	echo "Info: Decompressing ..." && zst -ck \
		-d /tmp/$CONF.zst >$CONF_DIR/$CONF && rm /tmp/$CONF.zst
fi
# [ -r $CONF_DIR/$CONF ] && mv $CONF_DIR/$CONF $CONF_DIR/$CONF.bak
# write wpad.conf
[ -r $WORK_DIR/.wpad -a -x $WORK_DIR/wpad/wpad.sh ] && $WORK_DIR/wpad/wpad.sh
[ -x /usr/sbin/unbound-control ] && echo "Info: reloading unbound ..." && /usr/sbin/unbound-control reload
