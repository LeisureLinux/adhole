#!/bin/sh
# Generate ADBlock list from different source in unbound local-zone format with "always_null"
# Generate your own adblock list for your home LAN and
# Contribute your block_domains.txt and unblock_domains.txt
# Copyright: LeisureLinux(Bilibili ID)
#
# If need proxy, change the PROXY to your own
PROXY="--proxy socks5h://wpad.local:2023"
#
ZONE_FILE=$(dirname $0)/adhole.conf
BLOCK_URL=$(dirname $0)/block_urls.txt
# the contents of the URL in the list are only domain names plaintext
TEXT_URL=$(dirname $0)/text_urls.txt
#
BLOCK_DOM=$(dirname $0)/block_domains.txt
UNBLOCK_DOM=$(dirname $0)/unblock_domains.txt
TMP_FILE=/tmp/$(basename $ZONE_FILE).tmp

touch $ZONE_FILE $ZONE_FILE.zst $BLOCK_URL $BLOCK_DOM $UNBLOCK_DOM $TMP_FILE $TEXT_URL
[ ! -x /usr/bin/zst ] && echo "Error: to save space, please install zst package" && exit 1

counts() {
	[ -r "$1" ] && echo "Info: Blocked $(grep "^local-zone" $1 | wc -l) domains"
}

block_text() {
	AD_URL=$1
	echo "Info: Grabbing $AD_URL ..."
	# remove IPs in the list with grep -vP
	curl $PROXY -sSL $AD_URL | grep -v "^#" | dos2unix -k \
		-q | sed 's/^0\.0\.0\.0 //g' | sed 's/^127\.0\.0\.1 //g' | grep \
		. | grep -v -P '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -v \
		"localhost" | grep . | awk '{print "local-zone: \""$1"\" always_null\n"}' >>$TMP_FILE
	[ $? != 0 ] && echo "Error: grab $AD_URL failed!" && return
	counts $TMP_FILE
}

block() {
	# convert to unbound always_null syntax
	AD_URL=$1
	echo "Info: Grabbing $AD_URL ..."
	curl $PROXY -sSL $AD_URL | grep '^0\.0\.0\.0' | awk '{print "local-zone: \""$2"\" always_null\n"}' | grep . >>$TMP_FILE
	[ $? != 0 ] && echo "Error: grab $AD_URL failed!" && return
	counts $TMP_FILE
}

# Main Prog.
[ -n "$PROXY" ] && echo "Info: Using: $PROXY"

#
AD_URL="https://unbound.oisd.nl/"
echo "Info: Grabbing $AD_URL ..."
curl $PROXY -sSL $AD_URL -o $TMP_FILE
[ $? != 0 ] && echo "Error: grab $AD_URL failed!" && exit 1
counts $TMP_FILE
#
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
grep -v "^#" $BLOCK_DOM | awk '{print "local-zone: \"" $1 "\" always_null"}' >>$TMP_FILE
counts $TMP_FILE
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
grep -v "0.0.0.0" $TMP_FILE | sed -e 's/\."/"/g' | grep -E -v "$exclude_domain" | sort | uniq | tee -a $ZONE_FILE >/dev/null
rm $TMP_FILE
echo "Info: results after deduplication:"
counts $ZONE_FILE
echo "Info: compressing $ZONE_FILE ..."
zst $ZONE_FILE
