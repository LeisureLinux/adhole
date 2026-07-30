#!/bin/sh
# release.sh — 构建+发布管线（合并版）
# 来源：data/gh-upload.sh + pull_zone.sh
#
# 用法:
#   ./release.sh build        # 运行 adhole.sh 生成 zone 文件
#   ./release.sh upload       # 将产物上传到 GitHub Release
#   ./release.sh pull         # 从 GitHub 拉取并重载 zone 文件
#   ./release.sh sync         # 三步流水线：build → upload → pull

set -e

GITHUB_OWNER="LeisureLinux"
REPO_NAME="adhole"
RELEASE_TAG="adhole"
ZONE_URL="https://github.com/${GITHUB_OWNER}/${REPO_NAME}/releases/download/${RELEASE_TAG}/adhole.conf.zst"
STATUS_URL="${ZONE_URL%/}/adhole_status.txt"
CONF_DIR="/etc/unbound/adhole"
DAYS=7

# ---------- build: 构建 zone 文件 ----------
do_build() {
	SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
	DATA_DIR="$SCRIPT_DIR/data"
	WORK_DIR="$DATA_DIR/result"

	echo "Info: Building adhole zone config..."
	mkdir -p "$WORK_DIR"
	cd "$WORK_DIR"

	if ! [ -x "$DATA_DIR/adhole.sh" ]; then
		echo "Error: data/adhole.sh not found or not executable!"
		exit 1
	fi

	"$DATA_DIR/adhole.sh"
	echo "Build complete."
}

# ---------- upload: 上传到 GitHub Release ----------
do_upload() {
	SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
	DATA_DIR="$SCRIPT_DIR/data"
	WORK_DIR="$DATA_DIR/result"

	[ ! -x /usr/bin/gh ] && echo "Error: github cli (gh) not found!" && exit 1
	gh auth status >/dev/null || { echo "Error: gh auth not configured!" && exit 1; }
	echo "Info: GitHub CLI OK."

	if [ -s "$WORK_DIR/adhole_status.txt" ] && [ -s "$WORK_DIR/adhole.conf.zst" ]; then
		echo "Info: Uploading assets to release ${RELEASE_TAG}..."
		for a in adhole_status.txt adhole.conf.zst; do
			gh release delete-asset -y "$RELEASE_TAG" "$a" 2>/dev/null || true
		done
		gh release upload "$RELEASE_TAG" "$WORK_DIR/adhole_status.txt" "$WORK_DIR/adhole.conf.zst"
		echo "Upload complete."
	else
		echo "Error: Required files not found in $WORK_DIR"
		exit 1
	fi
}

# ---------- pull: 从 GitHub 拉取并重载 ----------
do_pull() {
	[ ! -x /usr/bin/zstd ] && echo "Error: Please install zstd package" && exit 1

	# Proxy: ~/.proxy file first, then ALL_PROXY env
	CURL_OPTS=""
	PFILE="$HOME/.proxy"
	if [ -r "$PFILE" ]; then
		CURL_OPTS="--proxy $(cat "$PFILE")"
		echo "Info: Using proxy from $PFILE"
	else
		[ -n "${ALL_PROXY:-}" ] && CURL_OPTS="--proxy $ALL_PROXY"
	fi

	CURL="/usr/bin/curl -SL $CURL_OPTS"

	# If $1 is a local file path, just use it directly
	if [ -n "$1" ] && [ -r "$1" ]; then
		echo "Info: Reading local file $1 and decompressing..."
		sudo cp -- "$1" "$CONF_DIR"
		sudo zstd -f -d --output-dir-flat "$CONF_DIR" "$1"
		RELOAD=1
	else
		if [ ! -r "$CONF_DIR/adhole.conf" ] || [ "$(find "$CONF_DIR/adhole.conf" -mtime +"$DAYS" 2>/dev/null)" ]; then
			echo "Info: Downloading zone config from GitHub..."
			if ! $CURL "$ZONE_URL" -o "/tmp/adhole.conf.zst"; then
				echo "Error: Download failed!"
				exit 1
			fi
			$CURL "$STATUS_URL" -o "/tmp/adhole_status.txt"
			grep -v '^#' /tmp/adhole_status.txt | grep . || true
			echo "Info: Decompressing..."
			if zstd -d -f --output-dir-flat "$CONF_DIR" /tmp/adhole.conf.zst; then
				RELOAD=1
			else
				echo "Error: Decompression failed!"
				exit 1
			fi
		else
			echo "Info: Zone file is fresh (< $DAYS days old), skipping download."
		fi
	fi

	if [ "$RELOAD" = "1" ]; then
		if [ -x /usr/sbin/unbound-control ]; then
			echo "Info: Reloading unbound zone..."
			/usr/sbin/unbound-control reload
		fi
	fi
}

# ---------- sync: 全链路 ----------
do_sync() {
	echo "===== Step 1/3: Build ====="
	do_build
	echo ""
	echo "===== Step 2/3: Upload ====="
	do_upload
	echo ""
	echo "===== Step 3/3: Pull ====="
	do_pull
	echo ""
	echo "Sync pipeline complete! ✓"
}

# ===================== 主入口 =====================

case "${1:-help}" in
	build)
		do_build
		;;
	upload)
		do_upload
		;;
	pull)
		shift; do_pull "$@"
		;;
	sync)
		do_sync
		;;
	help|--help|-h)
		echo "构建+发布管线（release.sh）"
		echo ""
		echo "用法:"
		echo "  release.sh build      运行 adhole.sh 生成 adblock zone 配置文件"
		echo "  release.sh upload     将产物上传到 GitHub Release"
		echo "  release.sh pull [file] 从 GitHub 拉取 zone 文件并重载 Unbound"
		echo "                         可指定本地文件 path 直接解压部署"
		echo "  release.sh sync       三步流水线: build → upload → pull"
		echo "  release.sh help       显示此帮助"
		;;
	*)
		echo "Unknown subcommand: $1"
		echo "Run '$0 help' for usage."
		exit 1
		;;
esac
