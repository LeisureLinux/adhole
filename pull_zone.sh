#!/bin/sh
# Run as root cron
# pull the latest adhole.conf.zst from github, zone file already verified before uploading to github.
# put your proxy server e.g. http://IP:port or socks5://IP:port to ~/.proxy
PFILE="$HOME/.proxy"
[ -r "$PFILE" ] && PROXY="--proxy $(cat "$PFILE")" || echo "设置代理服务器能加速从 github 拉取 zone 文件的速度"
[ ! -x /usr/bin/zstd ] && echo "Error: Please install zstd package" && exit
#
URL="https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole.conf.zst"
# Only check local zone file 7 days old
DAYS=7
#
CONF="adhole.conf"
STATUS="adhole.status"
CONF_DIR="/etc/unbound/adhole"
#
# Main Prog.
# if exist $1 and readable, then just use the local file
if [ -r "$1" ]; then
	echo "Info: reading $1 and decompressing ... "
	sudo cp "$1" /etc/unbound/adhole
	sudo zstd -f -d /etc/unbound/adhole/"$(basename "$1")"
	RELOAD=1
else
	if [ ! -r $CONF_DIR/$CONF ] || [ "$(find $CONF_DIR/$CONF -mtime +"$DAYS" 2>/dev/null)" ]; then
		echo "Info: Downloading zone config $CONF.zst file from github ..."
		if ! curl -SL "$PROXY" "$URL" -o "/tmp/$CONF.zst"; then
			echo "Error: Download $URL failed!"
			exit 1
		fi
		# grab status
		curl -sSL "$PROXY" "$(dirname $URL)/$STATUS" -o "/tmp/$STATUS"
		# grep -v ^# /tmp/$STATUS | grep .
		head -4 /tmp/$STATUS
		echo "Info: Decompressing ..." && zstd -ck \
			-d /tmp/$CONF.zst | sudo tee $CONF_DIR/$CONF && rm /tmp/$CONF.zst
		RELOAD=1
	else
		echo "Info: $CONF is not expired yet, need $DAYS days to expire to avoid reload zone too frequently."
	fi
fi
[ "$RELOAD" = "1" ] && [ -x /usr/sbin/unbound-control ] && echo "Info: reloading unbound ..." && sudo /usr/sbin/unbound-control reload
