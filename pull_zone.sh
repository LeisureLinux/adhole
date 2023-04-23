#!/bin/sh
# Run as root cron
# pull the latest adhole.conf.zst from github
# put your proxy server e.g. http://IP:port or socks5://IP:port to .proxy
WORK_DIR=$(dirname $0)
PFILE="$WORK_DIR/.proxy"
[ -r "$PFILE" ] && PROXY="--proxy $(cat $PFILE)"
[ ! -x /usr/bin/zst ] && echo "Error: Please install zst package" && exit
#
URL="https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole.conf.zst"

CONF_DIR="/etc/unbound/adhole"
CONF=$(basename $URL .zst)
#
# Main Prog.
# if exist $1 and readable, then just use the local file
if [ -r "$1" ]; then
	echo "Info: reading $1 and decompressing ... "
	sudo cp $1 /etc/unbound/adhole
	sudo zst -f -d /etc/unbound/adhole/$(basename $1)
	RELOAD=1
else
	if [ ! -r $CONF_DIR/$CONF -o "$(find $CONF_DIR/$CONF -mtime +0 2>/dev/null)" ]; then
		echo "Info: downloading zone config $CONF.zst file from github ..."
		curl -sSL $PROXY $URL -o /tmp/$CONF.zst
		[ $? != 0 ] && echo "Error: Download $URL failed!" && exit 1
		echo "Info: Decompressing ..." && zst -ck \
			-d /tmp/$CONF.zst >$CONF_DIR/$CONF && rm /tmp/$CONF.zst
		RELOAD=1
	else
		echo "Info: $CONF is not expired yet."
	fi
fi
[ "$RELOAD" = "1" -a -x /usr/sbin/unbound-control ] && echo "Info: reloading unbound ..." && /usr/sbin/unbound-control reload
