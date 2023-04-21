#!/bin/sh
# Generate ADBlock list from different source in unbound local-zone format with "always_null"
# Generate your own adblock list for your home LAN and
# Contribute your block_domains.txt and unblock_domains.txt
# Copyright: LeisureLinux(Bilibili ID)
#
# use $0 -s to skip the big text urls
# touch ../.proxy as like: socks5://IP:port if need proxy
CURL_TIME="--connect-timeout 15"

WORK_DIR=$(dirname $0)
PFILE="$WORK_DIR/../.proxy"
[ -r "$PFILE" ] && PROXY="--proxy $(cat $PFILE)"
#
CACHE_DIR=$(dirname $0)/.cache
[ ! -d $CACHE_DIR ] && mkdir -p $CACHE_DIR
ZONE_FILE=$(dirname $0)/adhole.conf
BLOCK_URL=$(dirname $0)/block_urls.txt
# the contents of the URL in the list are only domain names plaintext
TEXT_URL=$(dirname $0)/text_urls.txt
#
BLOCK_DOM=$(dirname $0)/block_domains.txt
UNBLOCK_DOM=$(dirname $0)/unblock_domains.txt
ZONE_TMP_FILE=/tmp/$(basename $ZONE_FILE).tmp
cat /dev/null >$ZONE_TMP_FILE
#
STATUS="$WORK_DIR/status"

touch $ZONE_FILE.zst $BLOCK_URL $BLOCK_DOM $UNBLOCK_DOM $TMP_FILE $TEXT_URL
[ ! -x /usr/bin/zst ] && echo "Error: to save space, please install zst package" && exit 1

counts() {
	[ -r "$1" ] && echo "Info: Blocked $(grep "^local-zone" $1 | wc -l) domains"
}

file_age() {
	[ ! -r "$1" ] && return 2
	local file_age=$(date -r $1 +"%s")
	local now=$(date +"%s")
	[ $(($now - $file_age)) -gt 86400 ] && return 1 || return 0
}

grab_0000_head() {
	[ ! -r "$1" ] && return
	[ "$(grep -v '^#' $1 | grep . | tail -1 | awk '{print $1}')" = "0.0.0.0" ] && sed -n '1,/^0.0.0.0/p' $1 | grep -v "^0.0.0.0"
}

block_text() {
	AD_URL=$1
	local fname=$(basename $AD_URL)
	[ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}')".hosts"
	TMP_FILE=$CACHE_DIR/$fname
	file_age $TMP_FILE.status
	if [ $? = 0 ]; then
		echo "Info: no need to grab $AD_URL"
		cat $TMP_FILE >>$ZONE_TMP_FILE
		return
	fi
	echo "Info: Grabbing $AD_URL ..."
	# remove IPs in the list with grep -vP
	curl $PROXY $CURL_TIME -sSL $AD_URL >$TMP_FILE.curl
	[ $? != 0 ] && echo "Error: grab $AD_URL failed!" && return
	echo "URL: $AD_URL" >$TMP_FILE.status
	# Todo: grab head
	head -15 $TMP_FILE.curl >>$TMP_FILE.status
	grep -v "^#" $TMP_FILE.curl | dos2unix -k \
		-q | sed 's/^0\.0\.0\.0 //g' | sed 's/^127\.0\.0\.1 //g' | grep \
		. | grep -vP '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -v \
		"localhost" | awk '{print "local-zone: \""$1"\" always_null\n"}' | grep . >$TMP_FILE
	counts $TMP_FILE | tee -a $TMP_FILE.status
	rm $TMP_FILE.curl
	cat $TMP_FILE >>$ZONE_TMP_FILE
}

block() {
	# convert to unbound always_null syntax
	AD_URL=$1
	local fname=$(basename $AD_URL)
	[ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}')".hosts"
	TMP_FILE=$CACHE_DIR/$fname
	file_age $TMP_FILE.status
	if [ $? = 0 ]; then
		echo "Info: no need to grab $AD_URL"
		cat $TMP_FILE >>$ZONE_TMP_FILE
		return
	fi
	echo "Info: Grabbing $AD_URL ..."
	curl $PROXY $CURL_TIME -sSL $AD_URL >$TMP_FILE
	[ $? != 0 ] && echo "Error: grab $AD_URL failed!" && return
	# Pre-process remove some IP address
	grep -E -v '127.0.0.1|255.255.255|::' $TMP_FILE >$TMP_FILE.curl
	echo "URL: $AD_URL" >$TMP_FILE.status
	grab_0000_head $TMP_FILE.curl >>$TMP_FILE.status
	grep '^0\.0\.0\.0' $TMP_FILE.curl | awk '{print "local-zone: \""$2"\" always_null\n"}' | grep -v "0.0.0.0" | grep . >$TMP_FILE
	counts $TMP_FILE | tee -a $TMP_FILE.status
	rm $TMP_FILE.curl
	cat $TMP_FILE >>$ZONE_TMP_FILE
}

grab_oisd() {
	# Todo: Add back to Main
	AD_URL="https://unbound.oisd.nl/"
	TMP_FILE=$CACHE_DIR/$(basename $AD_URL)
	echo "Info: Grabbing $AD_URL ..."
	curl $PROXY $CURL_TIME -sSL $AD_URL -o $TMP_FILE
	if [ $? != 0 ]; then
		echo "Error: grab $AD_URL failed!"
	else
		echo $AD_URL >$TMP_FILE.status
		grep "^# Last modified:" >>$TMP_FILE.status
		# head -10 $TMP_FILE > $(get
		# awk '/Last modified:/ {print $NF}' $TMP_FILE
		# : 2023-04-21T12:06:19+0000"
		counts $TMP_FILE | tee -a $TMP_FILE.status
		echo >$TMP_FILE.status
		mv $TMP_FILE.status $TMP_FILE
	fi
}
#
# Main Prog.
if [ -n "$PROXY" ]; then
	echo "Info: Using: $PROXY checking Google ..."
	curl $PROXY $CURL_TIME -kIsS https://www.google.com/ >/dev/null
	[ $? != 0 ] && echo "Error: Failed to check Google!" && exit 1
fi

for url in $(grep -v "^#" $BLOCK_URL); do
	block $url
done

# use $0 -s to skip the big text urls
if [ "$1" != "-s" ]; then
	for url in $(grep -v "^#" $TEXT_URL); do
		block_text $url
	done
fi

#
echo "Info: Add local block domain list ..."
grep -v "^#" $BLOCK_DOM | awk '{print "local-zone: \"" $1 "\" always_null"}' >>$ZONE_TMP_FILE
# counts $TMP_FILE
#
mv $ZONE_FILE.zst $ZONE_FILE.zst.old 2>/dev/null
# Add head
T=$(date +"%Y-%m-%dT%H:%M:%S%z")
cat >$ZONE_FILE <<EOH
# Syntax: unbound
# Source: LeisureLinux
# URL: https://github.com/LeisureLinux/adhole
# UpdateTime: $T
EOH
# remove unblock domains from the generated block list and deduplicate
exclude_domain=$(grep -v "^#" $UNBLOCK_DOM | xargs | tr " " "|")
# e.g. exclude_domain="as.weixin.qq.com|pandora.xiaomi.com|cm.bilibili.com"
echo "Info: deduplicating ..."
grep -v "0.0.0.0" $ZONE_TMP_FILE | sed -e 's/\."/"/g' | grep -E -v "$exclude_domain" | sort | uniq >$ZONE_FILE
rm $ZONE_TMP_FILE
echo "Info: results after deduplication:"
counts $ZONE_FILE
echo "Info: compressing $ZONE_FILE ..."
zst $ZONE_FILE
