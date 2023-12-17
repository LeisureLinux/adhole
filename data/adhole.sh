#!/usr/bin/env bash
# Generate ADBlock list from different source in unbound local-zone format with "always_null"
# Generate your own adblock list for your home LAN and
# Contribute your block_domains.txt and unblock_domains.txt
# Copyright: LeisureLinux(Bilibili ID)
#
# Use $0 -s to skip the big text urls
# Place ~/.proxy as like: socks5://IP:port if need proxy
CURL_TIME="--connect-timeout 15"
SORT='parsort'
PROXY=""
[ ! -x /usr/bin/parsort ] && echo "Warning: missing package: parallel" && SORT='sort'
[ ! -x /usr/bin/zst ] && echo "Error: to save space, please install zst package" && exit 1

WORK_DIR=$(dirname "$0")
[ ! -d "$WORK_DIR"/result ] && mkdir "$WORK_DIR"/result
[ -s "$HOME/.proxy" ] && PROXY="-x $(cat "$HOME/.proxy")"
CURL="/usr/bin/curl ${PROXY} ${CURL_TIME} --compressed -sSL"

CACHE_DIR=$HOME/.cache/adhole
[ ! -d "$CACHE_DIR" ] && mkdir -p "$CACHE_DIR"
#
ZONE_FILE=$WORK_DIR/result/adhole.conf
STATUS="$WORK_DIR"/result/adhole_status.txt
#
BLOCK_URL=$WORK_DIR/block_urls.txt
# the contents of the URL in the list are only domain names plaintext
TEXT_URL=$WORK_DIR/text_urls.txt
# Self-defined block and unblock domains
BLOCK_DOM=$WORK_DIR/block_domains.txt
UNBLOCK_DOM=$WORK_DIR/unblock_domains.txt
#
ZONE_TMP_FILE=/tmp/$(basename "${ZONE_FILE}").tmp

cat /dev/null >"$ZONE_TMP_FILE"
touch "$ZONE_FILE".zst "$BLOCK_URL" "$BLOCK_DOM" "$UNBLOCK_DOM" "$TEXT_URL"
#
counts() {
    [ -r "$1" ] && echo "Info: Blocked $(grep -c "^local-zone" "$1") domains"
}

file_age() {
    [ ! -r "$1" ] && return 2
    local file_age
    file_age=$(date -r "$1" +"%s")
    local now
    now=$(date +"%s")
    [ $(($now - $file_age)) -gt 86400 ] && return 1 || return 0
}

grab_0000_head() {
    [ ! -r "$1" ] && return
    [ "$(grep -v '^#' "$1" | grep . | tail -1 | awk '{print $1}')" = "0.0.0.0" ] && sed -n '1,/^0.0.0.0/p' "$1" | grep -v "^0.0.0.0"
}

block_text() {
    AD_URL=$1
    local fname
    fname=$(basename "$AD_URL")
    # for those with question mark, only grab the first part as filename
    fname=$(echo "$fname" | awk -F'?' '{print $1}')
    [ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}' | awk -F'?' '{print $1}')".hosts.txt"
    TMP_FILE=$CACHE_DIR/$fname
    if file_age "$TMP_FILE".status; then
        echo "Info: no need to grab $AD_URL"
        [ -r "$TMP_FILE" ] && cat "$TMP_FILE" >>"$ZONE_TMP_FILE"
        return
    fi
    echo "Info: Grabbing $AD_URL to $TMP_FILE ..."
    if ! $CURL "$AD_URL" >"$TMP_FILE".curl; then
        echo "Error: grab $AD_URL failed!"
        return
    fi
    echo "URL: $AD_URL" >"$TMP_FILE".status
    head -30 "$TMP_FILE".curl | grep '^#' | grep -v "#$" | grep . >"$TMP_FILE".head
    [ -s "$TMP_FILE".head ] && cat "$TMP_FILE".head >>"$TMP_FILE".status || echo "# No head from source" >>"$TMP_FILE".status
    rm "$TMP_FILE".head

    # remove IPs in the list with grep -vP
    grep -v "^#" "$TMP_FILE".curl | dos2unix -k \
        -q | sed 's/^0\.0\.0\.0 //g' | sed 's/^127\.0\.0\.1 //g' | grep \
        . | grep -vP '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -v \
        "localhost" | sed -e 's/||//g' -e 's/\^//g' | awk '{print "local-zone: \""$1"\" always_null\n"}' | grep . >"$TMP_FILE"
    counts "$TMP_FILE" | tee -a "$TMP_FILE.status"
    rm "$TMP_FILE.curl"
    cat "$TMP_FILE" >>"$ZONE_TMP_FILE"
}

block() {
    # convert to unbound "always_null" syntax
    AD_URL=$1
    local fname
    fname=$(basename "$AD_URL")
    [ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}')".hosts"
    TMP_FILE=$CACHE_DIR/$fname
    if file_age "$TMP_FILE".status; then
        echo "Info: no need to grab $AD_URL"
        [ -r "$TMP_FILE" ] && cat "$TMP_FILE" >>"$ZONE_TMP_FILE"
        return
    fi
    echo "Info: Grabbing $AD_URL to $TMP_FILE ..."
    if ! $CURL "$AD_URL" >"$TMP_FILE"; then
        # 	[ $? != 0 ] &&
        echo "Error: grab $AD_URL failed!" && return
    fi
    # Pre-process, remove some IP address
    grep -E -v '127.0.0.1|255.255.255|::' "$TMP_FILE" >"$TMP_FILE".curl
    echo "URL: $AD_URL" >"$TMP_FILE".status
    grab_0000_head "$TMP_FILE".curl >>"$TMP_FILE".status
    grep '^0\.0\.0\.0' "$TMP_FILE".curl | awk '{print "local-zone: \""$2"\" always_null\n"}' | grep -v "0.0.0.0" >"$TMP_FILE"
    counts "$TMP_FILE" | tee -a "$TMP_FILE".status
    rm "$TMP_FILE".curl
    cat "$TMP_FILE" >>"$ZONE_TMP_FILE"
    echo >>"$ZONE_TMP_FILE"
}

grab_oisd() {
    AD_URL="https://unbound.oisd.nl/"
    local fname
    fname=$(basename "$AD_URL")
    [ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}')".hosts"
    TMP_FILE=$CACHE_DIR/$(basename $AD_URL)
    if file_age "$TMP_FILE".status; then
        echo "Info: no need to grab $AD_URL"
        [ -r "$TMP_FILE" ] && cat "$TMP_FILE" >>"$ZONE_TMP_FILE"
        return
    fi
    echo "Info: Grabbing $AD_URL to $TMP_FILE ..."
    if ! $CURL $AD_URL -o "$TMP_FILE"; then
        echo "Error: grab $AD_URL failed!" && return
    fi
    echo "URL: $AD_URL" >"$TMP_FILE".status
    grep "^#" "$TMP_FILE" | grep . >>"$TMP_FILE".status
    counts "$TMP_FILE" | tee -a "$TMP_FILE".status
    cat "$TMP_FILE" >>"$ZONE_TMP_FILE"
}

gen_status() {
    echo "# =========================================" >"$STATUS"
    (
        echo "# LeisureLinux Adhole block domains sources "
        echo "# UpdateTime: $(date +"%Y-%m-%dT%H:%M:%S%z") "
        echo "# ========================================="
        echo "#"
    ) >>"$STATUS"
    for s in "$CACHE_DIR"/*.status; do
        grep . "$s" >>"$STATUS"
        echo >>"$STATUS"
    done
}
#
# Main Prog.
if [ -n "$PROXY" ]; then
    echo "Info: Checking proxy healthy..."
    if ! ${CURL} -kIsS https://www.google.com/ >/dev/null; then
        echo "Error: Failed to check Google!"
        exit 1
    else
        echo "Info: Proxy server reached google.com OK."
    fi
fi

grab_oisd

for url in $(grep -v "^#" "$BLOCK_URL"); do
    block "$url"
done

# use $0 -s to skip the big text urls to avoid huge zone file on small SBC
if [ "$1" != "-s" ]; then
    for url in $(grep -v "^#" "$TEXT_URL"); do
        block_text "$url"
    done
fi

echo "Info: Add local block domain list ..."
grep -v "^#" "$BLOCK_DOM" | grep . | awk '{print "local-zone: \"" $1 "\" always_null"}' >>"$ZONE_TMP_FILE"
#
mv "$ZONE_FILE".zst "$ZONE_FILE".zst.old 2>/dev/null
# Add head
T=$(date +"%Y-%m-%dT%H:%M:%S%z")
cat >"$ZONE_FILE" <<EOH
# Syntax: unbound
# Source: LeisureLinux
# URL: https://github.com/LeisureLinux/adhole
# UpdateTime: $T
EOH
# remove unblock domains from the generated block list and deduplicate
exclude_domain=$(grep -v "^#" "$UNBLOCK_DOM" | xargs | tr " " "|")
# e.g. exclude_domain="as.weixin.qq.com|pandora.xiaomi.com|cm.bilibili.com"
echo "Info: deduplicating ..."
time grep -v "0.0.0.0" "$ZONE_TMP_FILE" | sed -e 's/\."/"/g' | grep -E -v "$exclude_domain" | tr "[:upper:]" "[:lower:]" | $SORT -u >>"$ZONE_FILE"
rm "$ZONE_TMP_FILE"
echo "Info: results after deduplication:"
counts "$ZONE_FILE"
cat >/tmp/check.conf <<EOF
server:
include: "$ZONE_FILE"
EOF
if ! /usr/sbin/unbound-checkconf /tmp/check.conf 2>/dev/null; then
    echo "Error: Found error in $ZONE_FILE"
else
    echo "Info: compressing $ZONE_FILE ..."
    zst "$ZONE_FILE"
    gen_status
    "${WORK_DIR}"/gh-upload.sh
fi
rm /tmp/check.conf
