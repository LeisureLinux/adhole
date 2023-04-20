#!/bin/sh
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
CONF_DIR="/etc/unbound/adhole"
CONF=$(basename $URL .zst)
#
#
add_wpad() {
	# write wpad.conf
	HIP=$(hostname -I | awk '{print $1}')
	[ "$(dig -4 +short wpad. @localhost)" = "$HIP" ] && echo "Info: No need to \
update wpad. record" && return
	echo "Adding wpad.local. record ..."
	# sudo unbound-control local_data wpad. A $HIP
	# sudo unbound-control local_data wpad.local. A $HIP
	cat >/etc/unbound/adhole/wpad.conf <<EOW
local-zone: "wpad." transparent
local-zone: "wpad.local." transparent
local-data: "wpad. IN A $HIP"
local-data: "wpad.local. IN A $HIP"
EOW
	RELOAD=1
	# [ $? != 0 ] && echo "Error: not able to update wpad. record!" && exit 6
	# [ "$(dig -4 +short wpad.local. @localhost)" != "$HIP" ] && echo "Error: added wpad not able to resolv!" && exit 7
	# echo "Congrats, All is well! Added wpad. as $HIP"
}

# Main Prog.
add_wpad
# if exist $1 and readable, then just use the local file
if [ -r "$1" ]; then
	sudo cp $1 /etc/unbound/adhole
	sudo zst -f -d /etc/unbound/adhole/$(basename $1)
	RELOAD=1
else
	if [ ! -r $CONF_DIR/$CONF -o "$(find $CONF_DIR/$CONF -mtime +0 2>/dev/null)" ]; then
		echo "Info: downloading zone config $CONF.zst file from github ..."
		curl -sS $PROXY $URL -o /tmp/$CONF.zst
		[ $? != 0 ] && echo "Error: Download $URL failed!" && exit 1
		echo "Info: Decompressing ..." && zst -ck \
			-d /tmp/$CONF.zst >$CONF_DIR/$CONF && rm /tmp/$CONF.zst
		RELOAD=1
	else
		echo "Info: $CONF is not expired yet."
	fi
fi
# [ -r $CONF_DIR/$CONF ] && mv $CONF_DIR/$CONF $CONF_DIR/$CONF.bak
[ "$RELOAD" = "1" -a -x /usr/sbin/unbound-control ] && echo "Info: reloading unbound ..." && /usr/sbin/unbound-control reload
