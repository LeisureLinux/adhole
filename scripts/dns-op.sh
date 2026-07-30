#!/bin/bash
# dns-op.sh — DNS 运维工具集（合并版）
# 来源：utils/flush_zone.sh + utils/add-sshfp.sh
#
# 用法:
#   dns-op.sh flush <hostname...>       — 对比本地 vs Google 解析，不一致则清理缓存
#   dns-op.sh sshfp <ssh-host>          — 生成 SSHFP 记录注入 Unbound


UNBOUND_CONTROL="/usr/sbin/unbound-control"

# ---------- 公共检查 ----------
check_root() {
	[ "$UID" != 0 ] && echo "Error: Need root to run!" && exit 3
}

check_unbound() {
	[ ! -x "$UNBOUND_CONTROL" ] && echo "Error: unbound-control not found at $UNBOUND_CONTROL" && exit 1
}

# ---------- flush: 检查解析并清理缓存 ----------
do_flush() {
	[ -z "${1+x}" ] || [ $# -eq 0 ] && echo "Syntax: $0 flush <hostname ...>" && exit 2
	check_unbound

	for d in "$@"; do
		L_IP=$(dig -t A +short "$d" @127.0.0.1 2>/dev/null)
		if [ -z "$L_IP" ]; then
			echo "Error in local resolving $d!"
			exit 10
		fi

		G_IP=$(dig -t A +short "$d" @8.8.8.8 2>/dev/null)
		if [ -z "$G_IP" ]; then
			echo "Error in Google resolving $d!"
			exit 11
		fi

		if [ "$L_IP" != "$G_IP" ]; then
			echo "\"$d\": Local=$L_IP; Google=$G_IP, flushing zone ..."
			"$UNBOUND_CONTROL" flush "$d"
			echo "Sleeping 10 seconds ..."
			sleep 10
		else
			echo "Domain $d is good."
		fi
	done
}

# ---------- sshfp: 生成并注入 SSHFP 记录 ----------
do_sshfp() {
	[ -z "${1+x}" ] || [ $# -eq 0 ] && echo "Syntax: $0 sshfp <ssh-host>" && exit 2
	check_unbound

	SSH_HOST="$1"
	ssh-keygen -r "$SSH_HOST" | sed 's/^/unbound-control local_data /;/ SSHFP . 1 /d;'
}

# ---------- 主入口 ----------
case "${1:-help}" in
	flush)
		shift; do_flush "$@"
		;;
	sshfp)
		shift; do_sshfp "$@"
		;;
	help|--help|-h)
		echo "DNS 运维工具集（dns-op.sh）"
		echo ""
		echo "用法:"
		echo "  $0 flush <hostname ...>    对比本地 vs Google 解析，不一致则清理 Unbound 缓存"
		echo "  $0 sshfp <ssh-host>        生成 SSHFP 记录并注入 Unbound"
		echo "  $0 help                    显示此帮助信息"
		;;
	*)
		echo "Unknown subcommand: $1"
		echo "Run '$0 help' for usage."
		exit 1
		;;
esac
