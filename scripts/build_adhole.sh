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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# If script is in scripts/, data dir is parent/data
case "$SCRIPT_DIR" in
*/scripts) WORK_DIR="$SCRIPT_DIR/../data" ;;
*) WORK_DIR="$SCRIPT_DIR" ;;
esac
[ ! -d "$WORK_DIR"/result ] && mkdir "$WORK_DIR"/result
[ -s "$HOME/.proxy" ] && PROXY="-x $(cat "$HOME/.proxy")"
CURL="/usr/bin/curl ${PROXY} ${CURL_TIME} --compressed -sSL"

CACHE_DIR=$HOME/.cache/adhole
[ ! -d "$CACHE_DIR" ] && mkdir -p "$CACHE_DIR"
#
ZONE_FILE=$WORK_DIR/result/adhole.conf
STATUS="$WORK_DIR"/result/adhole_status.txt
# Grab log: per-run log of all fetch / grab actions
GRAB_LOG="$WORK_DIR/result/grab_$(date +%Y%m%d_%H%M%S).log"
#
BLOCK_URL=$WORK_DIR/block_urls.txt
THREAT_URL=$WORK_DIR/threat_urls.txt
# Adblock Plus / uBlock filter lists (e.g. Brave), processed by grab_adblock()
ADBLOCK_URL=$WORK_DIR/adblock_urls.txt
# the contents of the URL in the list are only domain names plaintext
TEXT_URL=$WORK_DIR/text_urls.txt
# Self-defined block and unblock domains
BLOCK_DOM=$WORK_DIR/block_domains.txt
UNBLOCK_DOM=$WORK_DIR/unblock_domains.txt
#
ZONE_TMP_FILE=/tmp/$(basename "${ZONE_FILE}").tmp



# ======================================================================
# Argument parsing & configuration
# ======================================================================

show_help() {
    local lang="en"
    # Detect Chinese locale: only match zh_CN* / zh_TW*, everything else defaults to English
    _locale="${LANG:-}${LC_ALL:-}"
    case "$_locale" in
        zh_CN*|zh_TW*) lang="zh" ;;
    esac

    if [ "$lang" = "zh" ]; then
        echo "用法: $0 [选项]"
        echo ""
        echo "说明："
        echo "  从多个黑名单源抓取域名，去重后生成 Unbound always_null zone 文件。"
        echo "  使用 scripts/main.sh sync 可完成 build/upload/pull 全链路。"
    else
        echo "Usage: $0"
        echo ""
        echo "Description:"
        echo "  Fetches domains from multiple blacklist sources, deduplicates,"
        echo "  and generates a Unbound always_null zone file."
        echo "  Use scripts/main.sh sync for the full build/upload/pull pipeline."
    fi
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Warning: unknown option "$arg", ignoring."
            ;;
    esac
done

cat /dev/null >"$ZONE_TMP_FILE"
touch "$ZONE_FILE".zst "$BLOCK_URL" "$BLOCK_DOM" "$UNBLOCK_DOM" "$TEXT_URL" "$ADBLOCK_URL"

# log(): print a message to both stdout and the grab log
log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$GRAB_LOG"
}

# clean_old_grab_logs(): delete grab_*.log files older than 10 days in result/
clean_old_grab_logs() {
	# -mtime +10 = modification time strictly greater than 10*24h ago
	local removed
	removed=$(find "$WORK_DIR/result" -maxdepth 1 -type f -name 'grab_*.log' -mtime +10 -print -delete 2>/dev/null | wc -l)
	if [ "$removed" -gt 0 ]; then
		log "Info: cleaned $removed old grab log file(s) (>10 days) from $WORK_DIR/result"
	else
		log "Info: no old grab log files (>10 days) to clean in $WORK_DIR/result"
	fi
}
#
counts() {
	[ -r "$1" ] && echo "Info: Blocked $(grep -c "^local-zone" "$1") domains"
}

# ======================================================================
file_age() {
	[ ! -r "$1" ] && return 2
	local file_age
	file_age=$(date -r "$1" +"%s")
	local now
	now=$(date +"%s")
	[ $(($now - $file_age)) -gt 86400 ] && return 1 || return 0
}

# payload_complete(): the last non-empty line of a payload must be a complete
# "local-zone: ..." entry. A run killed mid-write can leave a payload truncated
# mid-line (e.g. ending in 'local-zon'), which would otherwise fuse with the
# first line of the next source and produce a corrupt zone file.
payload_complete() {
	awk 'NF{last=$0} END{exit !(last ~ /^local-zone: ".+" always_null$/)}' "$1"
}

# valid_payload(): payload is reusable from cache only if it is non-empty AND
# complete. Empty means the source yielded nothing (or died before writing a
# single entry), so we refetch rather than trust it.
valid_payload() {
	[ -s "$1" ] || return 1
	payload_complete "$1"
}

# cache_usable(): cache is reusable only when the .status marker is fresh AND
# the payload itself is complete. Never trust .status alone.
cache_usable() {
	file_age "$1".status && valid_payload "$1"
}

# append_zone(): append a source payload to the running zone file, always
# terminating the appended block with a newline so a payload whose last line
# lacks one cannot fuse with the first line of the next source. An empty
# payload is a no-op; a truncated one is refused rather than silently corrupting
# the zone file.
append_zone() {
	[ -r "$1" ] || return 0
	[ -s "$1" ] || return 0
	if ! payload_complete "$1"; then
		log "Error: refusing to append truncated payload: $1"
		return 1
	fi
	cat "$1" >>"$ZONE_TMP_FILE"
	[ -n "$(tail -c1 "$1")" ] && echo >>"$ZONE_TMP_FILE"
	return 0
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
	if cache_usable "$TMP_FILE"; then
		log "Info: no need to grab $AD_URL"
		append_zone "$TMP_FILE" || exit 1
		return
	fi
	log "Info: Grabbing $AD_URL to $TMP_FILE ..."
	if ! $CURL "$AD_URL" >"$TMP_FILE".curl; then
		log "Error: grab $AD_URL failed!" && exit 1
		return
	fi
	STATUS_TMP="$TMP_FILE".status.new
	echo "URL: $AD_URL" >"$STATUS_TMP"
	head -30 "$TMP_FILE".curl | grep '^#' | grep -v "#$" | grep . >"$TMP_FILE".head
	[ -s "$TMP_FILE".head ] && cat "$TMP_FILE".head >>"$STATUS_TMP" || echo "# No head from source" >>"$STATUS_TMP"
	rm -f "$TMP_FILE".head


	# Enhanced block_text: universal format cleaner for any blacklist source
	# Handles: hosts format, bare domains, https:// URLs, existing local-zone, Adblock
	{
		cat "$TMP_FILE".curl | dos2unix -k -q | sed 's/\r$//' | \
		sed -n '/^[[:space:]]*local-zone:/p' | grep -c '.' > /tmp/_bt_lz || true; \
		_has_lz=$(cat /tmp/_bt_lz); rm -f /tmp/_bt_lz; \
		if [ "$_has_lz" -gt 0 ]; then
			{
				sed -n 's/.*local-zone:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP_FILE".curl; \
				grep -v '^local-zone:' "$TMP_FILE".curl | sed 's/^0\.0\.0\.0 //g;s/^127\.0\.0\.1 //g'
			} | grep '\.' | sed 's/[[:space:]]*$//; s/^[[:space:]]*//' | \
			grep -vE '^[#!]' | sed -e 's/||//g' -e 's/\^//g' | sed 's/^\*\.\?//' | \
			sed -E 's#^(https?://)?##; s#/+$##; s#^www\.##' | \
			awk '{if ($0 ~ /\./ && length($0) > 2) print "local-zone: \"" $0 "\" always_null\n"}' | \
			grep '"[^ ]*"'
		else
			grep -vE '^[[:space:]]*(#|!|$)' "$TMP_FILE".curl | \
			sed 's/^0\.0\.0\.0 //g; s/^127\.0\.0\.1 //g' | \
			grep '\.' | grep -vP '\b(?:[0-9]{1,3}\.){3}[0-9]{3}\b' | grep -v "localhost" | \
			sed -e 's/||//g' -e 's/\^//g' | sed 's/^\*\.\?//' | \
			sed -E 's#^(https?://)?##; s#/+$##; s#^www\.##' | \
			awk '{if ($0 ~ /\./ && length($0) > 2) print "local-zone: \"" $0 "\" always_null\n"}' | \
			grep '"[^ ]*"'
		fi
	} >"$TMP_FILE"

	counts "$TMP_FILE" | tee -a "$STATUS_TMP"
	rm -f "$TMP_FILE.curl"
	mv "$STATUS_TMP" "$TMP_FILE".status
	append_zone "$TMP_FILE" || exit 1
}


# grab_adblock(): fetch an Adblock Plus / uBlock filter list (e.g. Brave) and convert
# only whole-domain block rules (||domain.tld^) into unbound always_null format.
# Rules with URL paths, $domain= scoping, cosmetic (##), scriptlet (#@#/##+js),
# and exception (@@) entries cannot be expressed at DNS level and are skipped.
grab_adblock() {
	AD_URL=$1
	local fname
	fname=$(basename "$AD_URL")
	fname=$(echo "$fname" | awk -F'?' '{print $1}')
	TMP_FILE=$CACHE_DIR/$fname
	if cache_usable "$TMP_FILE"; then
		log "Info: no need to grab $AD_URL"
		append_zone "$TMP_FILE" || exit 1
		return
	fi
	log "Info: Grabbing $AD_URL to $TMP_FILE ..."
	if ! $CURL "$AD_URL" >"$TMP_FILE".curl; then
		log "Error: grab $AD_URL failed!" && exit 1
	fi
	STATUS_TMP="$TMP_FILE".status.new
	echo "URL: $AD_URL" >"$STATUS_TMP"
	head -30 "$TMP_FILE".curl | grep '^!' | grep . >"$TMP_FILE".head
	[ -s "$TMP_FILE".head ] && cat "$TMP_FILE".head >>"$STATUS_TMP" || echo "# No head from source" >>"$STATUS_TMP"
	rm -f "$TMP_FILE".head

	# Keep only whole-domain block rules: ||domain.tld^, no path, no @@ exception,
	# no $option scoping. Order matters: the raw rule must be tested for 'domain='
	# BEFORE the domain is extracted, otherwise the option text is discarded and
	# the rule degenerates into a global block of a shared host
	# (e.g. ||fastly.net^$...,domain=cbs.com would block all of fastly.net).
	{
		grep -E '^\|\|' "$TMP_FILE".curl \
		| grep -v '^@@' \
		| grep -v '/' \
		| grep -v 'domain=' \
		| sed -n -E 's/^\|\|([a-zA-Z0-9_.-]+).*/\1/p' \
		| grep -E '^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*\.[a-zA-Z]{2,}$' \
		| tr '[:upper:]' '[:lower:]' \
		| awk '{print "local-zone: \"" $0 "\" always_null\n"}' \
		| grep '"[^ ]*"'
	} >"$TMP_FILE"

	counts "$TMP_FILE" | tee -a "$STATUS_TMP"
	rm -f "$TMP_FILE".curl
	mv "$STATUS_TMP" "$TMP_FILE".status
	append_zone "$TMP_FILE" || exit 1
}

block() {
	# convert to unbound "always_null" syntax
	AD_URL=$1
	local fname
	fname=$(basename "$AD_URL")
	[ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}')".hosts"
	TMP_FILE=$CACHE_DIR/$fname
	if cache_usable "$TMP_FILE"; then
		log "Info: no need to grab $AD_URL"
		append_zone "$TMP_FILE" || exit 1
		return
	fi
	log "Info: Grabbing $AD_URL to $TMP_FILE ..."
	# Retry loop (GitHub raw is flaky behind the GFW)
	MAX_RETRY=3
	RETRY=0
	SUCCESS=0
	while [ $RETRY -lt $MAX_RETRY ]; do
		if $CURL "$AD_URL" >"$TMP_FILE"; then
			SUCCESS=1
			break
		fi
		RETRY=$((RETRY + 1))
		if [ $RETRY -lt $MAX_RETRY ]; then
			log "Warning: grab attempt $RETRY failed for $AD_URL, retrying in 5s..."
			sleep 5
		fi
	done
	if [ -z "$FINAL_COUNT" ]; then
		FINAL_COUNT=$(grep -c "^local-zone" "$ZONE_FILE" 2>/dev/null || echo 0)
	fi
	echo "Info: Blocked ${FINAL_COUNT} domains (final deduplicated)" >>"$STATUS"
	if [ $SUCCESS -eq 0 ]; then
		log "Error: grab $AD_URL failed after $MAX_RETRY attempts!" && exit 1
	fi
	# Pre-process, remove some IP address
	grep -E -v '127.0.0.1|255.255.255|::' "$TMP_FILE" >"$TMP_FILE".curl
	STATUS_TMP="$TMP_FILE".status.new
	echo "URL: $AD_URL" >"$STATUS_TMP"
	grab_0000_head "$TMP_FILE".curl >>"$STATUS_TMP"
	grep '^0\.0\.0\.0' "$TMP_FILE".curl | awk '{print "local-zone: \""$2"\" always_null\n"}' | grep -v "0.0.0.0" >"$TMP_FILE"
	counts "$TMP_FILE" | tee -a "$STATUS_TMP"
	rm -f "$TMP_FILE".curl
	mv "$STATUS_TMP" "$TMP_FILE".status
	append_zone "$TMP_FILE" || exit 1
	echo >>"$ZONE_TMP_FILE"
}

grab_oisd() {
	AD_URL="https://unbound.oisd.nl/"
	local fname
	fname=$(basename "$AD_URL")
	[ "$fname" = "hosts" ] && fname=$(echo "$AD_URL" | awk -F/ '{print $(NF - 1)}')".hosts"
	TMP_FILE=$CACHE_DIR/$(basename $AD_URL)
	if cache_usable "$TMP_FILE"; then
		log "Info: no need to grab $AD_URL"
		append_zone "$TMP_FILE" || exit 1
		return
	fi
	log "Info: Grabbing $AD_URL to $TMP_FILE ..."
	if ! $CURL $AD_URL -o "$TMP_FILE"; then
		log "Error: grab $AD_URL failed!" && exit 1
	fi
	STATUS_TMP="$TMP_FILE".status.new
	echo "URL: $AD_URL" >"$STATUS_TMP"
	grep "^#" "$TMP_FILE" | grep . >>"$STATUS_TMP"
	counts "$TMP_FILE" | tee -a "$STATUS_TMP"
	mv "$STATUS_TMP" "$TMP_FILE".status
	append_zone "$TMP_FILE" || exit 1
}

gen_status() {
	local FINAL_COUNT="${1:-}"
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
	if [ -z "$FINAL_COUNT" ]; then
		FINAL_COUNT=$(grep -c "^local-zone" "$ZONE_FILE" 2>/dev/null || echo 0)
	fi
	echo "Info: Blocked ${FINAL_COUNT} domains (final deduplicated)" >>"$STATUS"
	cat $STATUS >> $GRAB_LOG
}
#
# Main Prog.
log "==========================================="
log "adhole.sh started, log file: $GRAB_LOG"
log "WORK_DIR: $WORK_DIR"
log "CACHE_DIR: $CACHE_DIR"
log "ZONE_FILE: $ZONE_FILE"
log "Proxy: ${PROXY:-none}"

clean_old_grab_logs

if [ -n "$PROXY" ]; then
	log "Info: Checking proxy healthy..."
	if ! ${CURL} -kIsS https://www.google.com/ >/dev/null; then
		log "Error: Failed to check Google!"
		exit 1
	else
		log "Info: Proxy server reached google.com OK."
	fi
fi

grab_oisd

for url in $(grep -v "^#" "$BLOCK_URL"); do
	block "$url"
done

# use $0 -s to skip the big text urls to avoid huge zone file on small SBC
# if [ "$1" != "-s" ]; then
#     for url in $(grep -v "^#" "$TEXT_URL"); do
#         block_text "$url"
#     done
# fi


# Process threat intelligence sources (format auto-detection)
for url in $(grep -v "^#" "$THREAT_URL" 2>/dev/null); do
	block_text "$url"
done


# Process Brave / Adblock Plus (uBlock) whole-domain filter lists
log "Info: Processing Adblock filter lists (Brave) ..."
for url in $(grep -v "^#" "$ADBLOCK_URL" 2>/dev/null); do
	grab_adblock "$url"
done

log "Info: Add local block domain list ..."
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
log "Info: deduplicating ..."
time grep -v "0.0.0.0" "$ZONE_TMP_FILE" | sed -e 's/\."/"/g' | grep -E -v "$exclude_domain" | tr "[:upper:]" "[:lower:]" | awk -F"\"" '$2 ~ /^[a-zA-Z0-9.-]+$/ && $2 ~ /\./ && length($2)>2 {print}' | $SORT -u >>"$ZONE_FILE"
rm "$ZONE_TMP_FILE"
log "Info: results after deduplication:"
counts "$ZONE_FILE"
cat >"$ZONE_TMP_FILE".check <<EOF
server:
include: "$ZONE_FILE"
EOF
# Show unbound-checkconf's diagnostics instead of discarding them: the previous
# 2>/dev/null hid the offending line number, which is the whole point of the check.
if ! CHECK_OUT=$(/usr/sbin/unbound-checkconf "$ZONE_TMP_FILE".check 2>&1); then
	log "Error: Found error in $ZONE_FILE"
	log "$CHECK_OUT"
	exit 1
else
	FINAL_COUNT=$(grep -c "^local-zone" "$ZONE_FILE")
	log "Info: compressing $ZONE_FILE ..."
	zst "$ZONE_FILE"
	gen_status "$FINAL_COUNT"
fi
rm -f "$ZONE_TMP_FILE".check
