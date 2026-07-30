#!/bin/sh
# wpad-mgmt.sh — WPAD / Miera 运维管理脚本（合并版）
# 来源：wpad/setup_wpad.sh + wpad/wpad.sh + wpad/miera/install.sh + wpad/test_miera.sh
#
# 用法:
#   ./wpad-mgmt.sh deploy                # 部署 WPAD Web + systemd timer
#   ./wpad-mgmt.sh deconfig              # 卸载并清理配置
#   ./wpad-mgmt.sh update-dns            # 动态更新 WPAD DNS 记录
#   ./wpad-mgmt.sh mieru-install         # 安装 Miera 客户端（含 wpad.dat 生成）
#   ./wpad-mgmt.sh mieru-deconfig        # 停止并移除 Miera 相关服务
#   ./wpad-mgmt.sh mieru-wpad            # 只更新 wpad.dat
#   ./wpad-mgmt.sh mieru-status          # 查看 Miera 客户端状态
#   ./wpad-mgmt.sh test [-v]             # 全链路测试（可选子模块：-cfg -status -proxy -wpad -dns）

# ===================== 公共函数 =====================

error_exit() { echo "Error: $1"; exit "${2:-1}"; }

get_my_ip() {
	hostname -I 2>/dev/null | awk '{print $1}'
}

resolve_wpad() {
	dig -4 +short wpad @localhost 2>/dev/null | tail -1
}

check_sudo() {
	sudo -nv 2>/dev/null || error_exit "当前用户没有 sudo 能力" 1
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ===================== deploy: WPAD 部署 =====================

do_deploy() {
	check_sudo
	cd "$(dirname "$0")"
	echo "Info: 开始部署 WPAD ..."

	deconfig() {
		cat /dev/null | sudo tee /etc/unbound/adhole/wpad.conf >/dev/null 2>&1
		sudo systemctl --now disable wpad.service 2>/dev/null
		sudo systemctl --now disable wpad.timer 2>/dev/null
		sudo systemctl restart unbound 2>/dev/null
	}

	[ "${1:-}" = "deconfig" ] && deconfig && echo "Info: de-configured" && exit 0

	HIP=$(get_my_ip)
	[ -z "$HIP" ] && error_exit "获取本机 IP 失败" 5

	# 复制 wpad.sh 到 etc/unbound 目录
	sudo cp -f wpad/wpad.sh /etc/unbound
	sudo /etc/unbound/wpad.sh -f || error_exit "执行 wpad.sh 失败" 7

	echo "Info: 设置 WPAD timer ..."
	sudo cp -f wpad/wpad.timer wpad/wpad.service /etc/systemd/system
	sudo systemctl daemon-reload
	sudo systemctl --now enable wpad.timer wpad.service
	[ $? -ne 0 ] && error_exit "设置 wpad timer 失败" 8

	echo "Info: WPAD setup complete. Added wpad. as $HIP"
}

# ===================== update-dns: 动态更新 WPAD DNS 记录 =====================

do_update_dns() {
	RESOLVER=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | head -1)
	[ -z "$RESOLVER" ] && RESOLVER="127.0.0.1"

	if ! nc -4uvz "$RESOLVER" 53 2>/dev/null; then
		error_exit "DNS 服务未在 $RESOLVER 上运行" 5
	fi

	NIC=$(ip -j -br r s default | jq -r '.[] | select(.protocol=="dhcp") | .dev')
	[ -z "$NIC" ] && error_exit "未找到默认路由！" 1

	update=""
	RR4=""
	RR6=""
	V6_ALLOW=""

	# --- IPv4 ---
	HIP4=$(ip -4 -j -br add show "$NIC" | jq -r '.[].addr_info[].local' 2>/dev/null)
	echo "Info: v4 address: $HIP4"
	if [ -n "$HIP4" ]; then
		CIP4=$(dig -4 -t A +short wpad. @"$RESOLVER" 2>/dev/null)
		if [ "$CIP4" = "$HIP4" ]; then
			echo "Info: No need to update wpad. v4 record"
			RR4="local-data: \"wpad. 3600 IN A $CIP4\""
		else
			RR4="local-data: \"wpad. 3600 IN A $HIP4\""
			update=1
		fi
	fi

	# --- IPv6 ---
	if [ "$(cat /sys/module/ipv6/parameters/disable 2>/dev/null)" = "1" ]; then
		echo "Info: IPv6 disabled in OS, skipping."
	else
		HIP6=$(ip -6 -j add show "$NIC" | jq -r '.[].addr_info | .[] | select(.temporary==null and .mngtmpaddr==null) | (.prefixlen, .local)' | paste - - | awk '{print $NF}' | grep -iE '^fc|^fd' | tail -1)
		[ -z "$HIP6" ] && HIP6=$(ip -6 -j add show "$NIC" scope global | jq -r '.[].addr_info | .[] | select(.dynamic==true).local' | tail -1)
		if [ -z "$HIP6" ]; then
			echo "Info: IPv6 not configured, skipping."
		else
			echo "Info: v6 address: $HIP6"
			# 从路由器广告或手动配置的 fd/fc 前缀选择允许查询的网段
			V6_ALLOW=$(ip -6 -j route show dev "$NIC" | jq -r '.[] | select(.dst!="default") | .dst' | grep -v "^fe80" | sort -u)
			[ -n "$V6_ALLOW" ] && V6_ALLOW=$(echo "$V6_ALLOW" | awk '{print "access-control:", $0, "allow"}')
			echo "Info: v6 subnet to allow DNS query: $(echo $V6_ALLOW | tr '\n' ' ')"
			CIP6=$(dig -t AAAA +short wpad. @"$RESOLVER" 2>/dev/null)
			if [ "$CIP6" = "$HIP6" ]; then
				echo "Info: No need to update wpad. v6 record"
				RR6="local-data: \"wpad. 3600 IN AAAA $CIP6\""
			else
				RR6="local-data: \"wpad. 3600 IN AAAA $HIP6\""
				update=1
			fi
		fi
	fi

	[ -z "$update" ] && echo "Info: old record is OK" && exit 0

	WPAD_CONF="/etc/unbound/adhole/wpad.conf"
	[ ! -f "$WPAD_CONF" ] && echo "Warning: Zone file $WPAD_CONF does not exist, no need to reload zone." && exit 9

	# 检查 WPAD Web 是否可达
	if [ "$(curl -q -4 -kIsS -w '%{json}\n' http://wpad/wpad.dat 2>/dev/null | tail -1 | jq -r .http_code 2>/dev/null)" != "200" ]; then
		echo "Warning: Please setup wpad required web server first. e.g.: http://wpad/wpad.dat"
	fi

	# 写入并重载
	[ ! -d /etc/unbound/adhole ] && sudo mkdir -p /etc/unbound/adhole
	echo "Updating wpad. v4+v6 record ..."
	cat > "$WPAD_CONF" << EOW
local-zone: "wpad." transparent
$RR4
$RR6
$V6_ALLOW
EOW
	echo "Info: zone file:"
	cat "$WPAD_CONF"

	if ! /usr/sbin/unbound-checkconf /etc/unbound/unbound.conf; then
		error_exit "新配置文件未通过 unbound-checkconf" 9
	fi

	echo "Reloading zone config ..."
	/usr/sbin/unbound-control reload || error_exit "unbound-control reload failed"
	echo "All is well"
}

# ===================== mieru-install: Miera 一键安装 =====================

do_mieru_install() {
	SVC_NAME="my_mieru"
	PRX_PORT=8888
	MERA_CFG="$(dirname "$0")/../wpad/miera/client.json"

	chk_pkg() {
		PROG="libpacparser1 haveged jq curl iproute2 nginx"
		sudo dpkg-query -W $PROG >/dev/null 2>&1 || {
			echo "Info: Installing base dependencies..."
			sudo apt -y update
			sudo apt -y install $PROG
		}
	}

	apply_cfg() {
		[ ! -r "$MERA_CFG" ] && error_exit "client.json 配置文件不存在" 1
		echo "Info: Applying mieru configuration..."
		if ! sudo mieru apply config "$MERA_CFG"; then
			error_exit "mieru apply config 失败。请检查 client.json" 1
		fi
		echo "Info: Applied config:"
		mieru describe config
	}

	create_systemd_service() {
		[ -f /etc/systemd/system/mieru@.service ] && return 0
		cat <<EOS | sudo tee /etc/systemd/system/mieru@.service
[Unit]
Description=Mieru Proxy Client (%i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mieru start
ExecStop=/usr/local/bin/mieru stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOS
		echo "Info: Created /etc/systemd/system/mieru@.service"
	}

	gen_wpad() {
		WPAD_FILE="/var/www/html/wpad/wpad.dat"
		[ ! -L /var/www/html/wpad.dat ] && sudo ln -sf "$WPAD_FILE" /var/www/html
		PAC="PROXY ${IP}:${PRX_PORT}; DIRECT"
		check_local_port
		echo "Info: Generating $WPAD_FILE with PAC=$PAC ..."
		mkdir -p "$(dirname "$WPAD_FILE")"
		/usr/local/bin/genpac --format=pac --pac-proxy="$PAC" --proxy "socks5://127.0.0.1:$PRX_PORT" \
			| sudo tee "$WPAD_FILE" >/dev/null
		GOOGLE=$(pactester -p "$WPAD_FILE" -u https://www.google.com 2>/dev/null) || true
		BAIDU=$(pactester -p "$WPAD_FILE" -u https://www.baidu.com 2>/dev/null) || true
		if [ "$GOOGLE" != "$PAC" ] || [ "$BAIDU" != "DIRECT" ]; then
			echo "Warning: PAC validation warning. Google=$GOOGLE Baidu=$BAIDU (expected $PAC / DIRECT)"
		else
			echo "Info: $WPAD_FILE generated and validated ✓"
		fi
	}

	deconfig_all() {
		sudo systemctl --now disable mieru@$SVC_NAME 2>/dev/null || true
		sudo mieru stop 2>/dev/null || true
		sudo systemctl --now disable wpad.timer 2>/dev/null || true
		sudo systemctl --now disable wpad.service 2>/dev/null || true
		sudo rm -f /etc/systemd/system/wpad.timer /etc/systemd/system/wpad.service
		sudo unlink /var/www/html/wpad.dat 2>/dev/null || true
		sudo rm -f /var/www/html/wpad/wpad.dat 2>/dev/null || true
		sudo rm -f /etc/nginx/conf.d/wpad.conf 2>/dev/null || true
		sudo nginx -s reload 2>/dev/null || true
		sudo systemctl daemon-reload
		echo "Info: De-configured all mieru services."
	}

	check_local_port() {
		nc -zv 127.0.0.1 "$PRX_PORT" || {
			error_exit "本地代理服务端口 $PRX_PORT 未监听" 1
		}
	}

	check_wall() {
		echo "Info: Testing internet access via proxy..."
		curl -m 10 --proxy "http://127.0.0.1:$PRX_PORT" -kIsS https://www.google.com/ | head -3
	}

	# Sub-subcommand: mieru-deconfig
	[ "${1:-}" = "deconfig" ] && do_mieru_deconfig && exit 0

	# Sub-subcommand: mieru-wpad only
	if [ "${1:-}" = "wpad" ]; then
		chk_pkg
		IP=$(resolve_wpad)
		[ -z "$IP" ] && error_exit "wpad DNS 记录未配置！请先运行 deploy。" 1
		PRX_PORT=$(jq -r '.httpProxyPort // 8888' "$MERA_CFG")
		gen_wpad
		exit 0
	fi

	# Full install flow
	check_sudo
	chk_pkg
	apply_cfg

	PRX_PORT=$(jq -r '.httpProxyPort // 8888' "$MERA_CFG")
	echo "Info: HTTP proxy port: $PRX_PORT"

	IP=$(resolve_wpad)
	[ -z "$IP" ] && error_exit "wpad DNS 记录未配置！请先运行 deploy。" 1
	echo "Info: wpad resolved to $IP"

	PROXY="socks5 $IP:$PRX_PORT"

	create_systemd_service
	sudo systemctl daemon-reload

	echo "Info: Starting mieru client..."
	sudo systemctl enable mieru@$SVC_NAME
	sudo mieru start
	sleep 3

	check_wall

	# Generate wpad.dat if web server is ready
	mkdir -p /var/www/html/wpad
	if [ "$(curl -q -4 -kIsS -w '%{json}\n' http://wpad/wpad.dat 2>/dev/null | tail -1 | jq -r .http_code 2>/dev/null)" = "200" ]; then
		gen_wpad
	else
		echo "Warning: WPAD web server not ready. Run 'mieru-wpad' later after web server is up."
	fi

	echo "Congrats! Miera setup complete. ✓"
}

# ===================== mieru-deconfig: 停止移除 Miera 服务 =====================

do_mieru_deconfig() {
	SVC_NAME="my_mieru"
	echo "Info: Stopping and removing Miera services..."
	sudo systemctl --now disable mieru@$SVC_NAME 2>/dev/null || true
	sudo mieru stop 2>/dev/null || true
	sudo systemctl --now disable wpad.timer 2>/dev/null || true
	sudo systemctl --now disable wpad.service 2>/dev/null || true
	sudo rm -f /etc/systemd/system/wpad.timer /etc/systemd/system/wpad.service
	sudo unlink /var/www/html/wpad.dat 2>/dev/null || true
	sudo rm -f /var/www/html/wpad/wpad.dat 2>/dev/null || true
	sudo rm -f /etc/nginx/conf.d/wpad.conf 2>/dev/null || true
	sudo nginx -s reload 2>/dev/null || true
	sudo systemctl daemon-reload
	echo "Info: Miera services removed."
}

# ===================== test: 全链路验证测试 =====================

do_test() {
	set -e
	VERBOSITY=0
	[ "$1" = "-v" ] && VERBOSITY=1
	shift

	SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
	CFG_FILE="$SCRIPT_DIR/wpad/miera/client.json"
	WPAD_HOST="wpad"
	HTTP_PROXY_PORT=8888
	SOCKS5_PORT=1080
	PASS=0
	FAIL=0
	SKIP=0

	ok()     { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
	err()    { FAIL=$((FAIL+1)); echo "  ❌ FAIL: $1"; }
	warn()   { SKIP=$((SKIP+1)); echo "  ⚠️  WARN: $1"; }
	section() { echo ""; echo "===== $1 ====="; }

	test_cfg() {
		section "1. 配置文件验证"
		if [ ! -f "$CFG_FILE" ]; then err "配置文件不存在: $CFG_FILE"; return; fi
		jq . "$CFG_FILE" >/dev/null 2>&1 || { err "client.json 不是合法 JSON"; return; }
		ok "JSON 格式合法"

		name=$(jq -r '.profiles[0].user.name // empty' "$CFG_FILE")
		passwd=$(jq -r '.profiles[0].user.password // empty' "$CFG_FILE")
		server_ip=$(jq -r '.profiles[0].servers[0].ipAddress // empty' "$CFG_FILE")
		port_binding=$(jq -r '.profiles[0].servers[0].portBindings[0].port // empty' "$CFG_FILE")
		socks_port=$(jq -r '.socks5Port // empty' "$CFG_FILE")
		http_port=$(jq -r '.httpProxyPort // empty' "$CFG_FILE")

		[ -z "$name" ] || [ "$name" = "YOUR_USERNAME" ] && warn "username 仍是默认值" || ok "username 已配置"
		[ -z "$passwd" ] || [ "$passwd" = "YOUR_PASSWORD" ] && warn "password 仍是默认值" || ok "password 已配置"
		[ -z "$server_ip" ] || [ "$server_ip" = "PLACEHOLDER" ] && err "server IP 未配置" || ok "server IP 已配置: $server_ip"
		[ -z "$port_binding" ] || [ "$port_binding" = "YOUR_MITA_PORT" ] && err "mita port 未配置" || ok "mita port 已配置: $port_binding"
		[ -n "$socks_port" ] && ok "socks5Port: $socks_port"
		[ -n "$http_port" ] && { ok "httpProxyPort: $http_port"; HTTP_PROXY_PORT="$http_port"; }
		[ -n "$(jq -r '.profiles[0].mtu // empty' "$CFG_FILE")" ] && ok "MTU configured"
		[ -n "$(jq -r '.profiles[0].multiplexing.level // empty' "$CFG_FILE")" ] && ok "Multiplexing configured"
		[ -n "$(jq -r '.profiles[0].handshakeMode // empty' "$CFG_FILE")" ] && ok "Handshake mode configured"
	}

	test_status() {
		section "2. Miera 客户端状态"
		if has_cmd mieru; then
			ok "mieru 命令可用"
			status=$(mieru status 2>&1) || true
			echo "$status" | head -5
			echo "$status" | grep -qi "running\|started" && ok "Miera 正在运行" || err "Miera 未运行"
			config_out=$(mieru describe config 2>&1) || true
			echo "$config_out" | head -10
		else
			err "mieru 命令不存在（请先运行 installer）"
		fi
	}

	test_proxy() {
		section "3. 代理连通性测试"
		nc -z 127.0.0.1 "$SOCKS5_PORT" >/dev/null 2>&1 && ok "Socks5:$SOCKS5_PORT 监听中" || err "Socks5:$SOCKS5_PORT 未监听"
		nc -z 127.0.0.1 "$HTTP_PROXY_PORT" >/dev/null 2>&1 && ok "HTTP Proxy:$HTTP_PROXY_PORT 监听中" || err "HTTP Proxy:$HTTP_PROXY_PORT 未监听"

		result=$(curl -m 10 --proxy "http://127.0.0.1:$HTTP_PROXY_PORT" -kIsS https://www.google.com/ 2>/dev/null | head -1) || true
		echo "$result" | grep -q "^HTTP" && ok "HTTP 代理连通 Google ✓" || err "HTTP 代理无法访问 Google"
	}

	test_wpad() {
		section "4. WPAD/PAC 验证"
		WPAD_URL="http://${WPAD_HOST}/wpad.dat"
		code=$(curl -ms 5 "${WPAD_URL}" -o /dev/null -w "%{http_code}" 2>/dev/null) || code="000"
		if [ "$code" = "200" ]; then
			ok "WPAD 返回 200"
			wp_content=$(curl -s "${WPAD_URL}")
			line_count=$(echo "$wp_content" | wc -l)
			ok "PAC 文件有 $line_count 行规则"
		else
			err "WPAD 不可达 (HTTP $code)"
		fi
	}

	test_dns() {
		section "5. DNS 解析验证"
		wp_ip=$(dig +short "$WPAD_HOST" @localhost 2>/dev/null | tail -1)
		if [ -n "$wp_ip" ] && echo "$wp_ip" | grep -q '[0-9]'; then ok "DNS wpad → $wp_ip"; else err "DNS wpad 解析失败"; fi
		unbound-control dump_cache wpad >/dev/null 2>&1 && ok "Unbound DNS 正常" || warn "Unbound 控制接口可能未就绪"
	}

	case "${1:-all}" in
		-cfg)       test_cfg ;;
		-status)    test_status ;;
		-proxy)     test_proxy ;;
		-wpad)      test_wpad ;;
		-dns)       test_dns ;;
		all|-a)     test_cfg; test_status; test_proxy; test_wpad; test_dns ;;
		*)
			echo "用法: $0 test [-v] [-cfg|-status|-proxy|-wpad|-dns|all]"
			exit 1
			;;
	esac

	echo ""
	echo "=========================================="
	echo "测试结果: ✅ ${PASS} pass, ❌ ${FAIL} fail, ⚠️ ${SKIP} warn"
	echo "=========================================="
	[ $FAIL -gt 0 ] && exit 1
	exit 0
}

# ===================== 主入口 =====================

case "${1:-help}" in
	deploy)
		shift; do_deploy "$@"
		;;
	update-dns)
		do_update_dns
		;;
	mieru-install|miera-install)
		shift; do_mieru_install "$@"
		;;
	mieru-deconfig|miera-deconfig)
		shift; do_mieru_deconfig
		;;
	test)
		shift; do_test "$@"
		;;
	help|--help|-h)
		echo "WPAD / Miera 运维管理脚本（wpad-mgmt.sh）"
		echo ""
		echo "用法:"
		echo "  wpad-mgmt.sh deploy               部署 WPAD Web 服务 + systemd timer"
		echo "  wpad-mgmt.sh deconfig             禁用 WPAD 服务、清空配置"
		echo "  wpad-mgmt.sh update-dns           动态更新 WPAD A/AAAA DNS 记录"
		echo "  wpad-mgmt.sh mieru-install        安装 Miera 客户端 + 配置 + 生成 wpad.dat"
		echo "  wpad-mgmt.sh mieru-deconfig       移除所有 Miera 相关服务"
		echo "  wpad-mgmt.sh mieru-wpad           仅重新生成 wpad.dat"
		echo "  wpad-mgmt.sh mieru-status         查看 Miera 客户端状态"
		echo "  wpad-mgmt.sh test [-v]            全链路验证测试"
		echo "  wpad-mgmt.sh help                 显示此帮助"
		;;
	*)
		echo "Unknown subcommand: $1"
		echo "Run '$0 help' for usage."
		exit 1
		;;
esac
