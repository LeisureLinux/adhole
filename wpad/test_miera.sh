#!/bin/sh
# Mieru 客户端安装后验证测试脚本
# 替代原来的 SS/Kcptun/Goproxy 连通性检查
#
# 用法:
#   ./test_miera.sh [-v]           # 运行全部测试
#   ./test_miera.sh -cfg           # 只检查配置文件格式
#   ./test_miera.sh -status        # 只检查 mieru 进程状态
#   ./test_miera.sh -proxy         # 只检查代理连通性
#   ./test_miera.sh -wpad          # 只检查 WPAD PAC 文件
#   ./test_miera.sh -dns           # 只检查 DNS 查询

set -e
VERBOSITY=0
[ "$1" = "-v" ] && VERBOSITY=1

CFG_FILE="$(dirname $0)/miera/client.json"
WPAD_HOST="wpad"
HTTP_PROXY_PORT=8888
SOCKS5_PORT=1080
PASS=0
FAIL=0
SKIP=0

ok() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
err() { FAIL=$((FAIL+1)); echo "  ❌ FAIL: $1"; }
warn() { SKIP=$((SKIP+1)); echo "  ⚠️  WARN: $1"; }

section() {
	echo ""
	echo "===== $1 ====="
}

# --- 1. 检查 client.json 配置模板 ---
test_cfg() {
	section "1. 配置文件验证"
	if [ ! -f "$CFG_FILE" ]; then
		err "配置文件不存在: $CFG_FILE"
		return
	fi
	# JSON 合法性检查
	if ! jq . "$CFG_FILE" >/dev/null 2>&1; then
		err "client.json 不是合法的 JSON"
		return
	fi
	ok "JSON 格式合法"

	# 检查关键字段
	name=$(jq -r '.profiles[0].user.name // empty' "$CFG_FILE")
	passwd=$(jq -r '.profiles[0].user.password // empty' "$CFG_FILE")
	server_ip=$(jq -r '.profiles[0].servers[0].ipAddress // empty' "$CFG_FILE")
	port_binding=$(jq -r '.profiles[0].servers[0].portBindings[0].port // empty' "$CFG_FILE")
	socks_port=$(jq -r '.socks5Port // empty' "$CFG_FILE")
	http_port=$(jq -r '.httpProxyPort // empty' "$CFG_FILE")

	if [ -z "$name" ] || [ "$name" = "YOUR_USERNAME" ]; then
		warn "username 仍是默认值，部署前需替换 YOUR_USERNAME"
	else
		ok "username 已配置"
	fi

	if [ -z "$passwd" ] || [ "$passwd" = "YOUR_PASSWORD" ]; then
		warn "password 仍是默认值，部署前需替换 YOUR_PASSWORD"
	else
		ok "password 已配置"
	fi

	if [ -z "$server_ip" ] || [ "$server_ip" = "YOUR_SERVER_IP_OR_DOMAIN" ]; then
		err "server IP 未配置"
	else
		ok "server IP 已配置: $server_ip"
	fi

	if [ -z "$port_binding" ] || [ "$port_binding" = "YOUR_MITA_PORT" ]; then
		err "mita port 未配置"
	else
		ok "mita port 已配置: $port_binding"
	fi

	if [ -n "$socks_port" ]; then
		ok "socks5Port: $socks_port"
	fi

	if [ -n "$http_port" ]; then
		ok "httpProxyPort: $http_port"
		HTTP_PROXY_PORT=$http_port
	fi

	# 检查 mtu、multiplexing、handshakeMode 字段是否存在
	mtu=$(jq -r '.profiles[0].mtu // empty' "$CFG_FILE")
	multi=$(jq -r '.profiles[0].multiplexing.level // empty' "$CFG_FILE")
	handshake=$(jq -r '.profiles[0].handshakeMode // empty' "$CFG_FILE")

	[ -n "$mtu" ] && ok "MTU: $mtu"
	[ -n "$multi" ] && ok "Multiplexing: $multi"
	[ -n "$handshake" ] && ok "Handshake mode: $handshake"
}

# --- 2. 检查 mieru 客户端进程 ---
test_status() {
	section "2. Miera 客户端状态"

	if hash mieru 2>/dev/null; then
		ok "mieru 命令可用"

		status=$(mieru status 2>&1) || true
		echo "    Status output: $status"

		if echo "$status" | grep -qi "running\|started"; then
			ok "Miera 客户端正在运行"
		else
			err "Miera 客户端未运行"
		fi

		config_out=$(mieru describe config 2>&1) || true
		echo "    Config output:"
		echo "$config_out" | head -20
	else
		err "mieru 命令不存在（请先运行 install.sh）"
	fi
}

# --- 3. 检查代理连通性 ---
test_proxy() {
	section "3. 代理连通性测试"

	# socks5 端口检查
	if nc -z 127.0.0.1 "$SOCKS5_PORT" >/dev/null 2>&1; then
		ok "Socks5 端口 $SOCKS5_PORT 监听中"
	else
		err "Socks5 端口 $SOCKS5_PORT 未监听"
	fi

	# http proxy 端口检查
	if nc -z 127.0.0.1 "$HTTP_PROXY_PORT" >/dev/null 2>&1; then
		ok "HTTP Proxy 端口 $HTTP_PROXY_PORT 监听中"
	else
		err "HTTP Proxy 端口 $HTTP_PROXY_PORT 未监听"
	fi

	# 实际代理测试
	echo "Info: Testing HTTP proxy via Google..."
	result=$(curl -m 10 --proxy "http://127.0.0.1:$HTTP_PROXY_PORT" \
		-kIsS https://www.google.com/ 2>/dev/null | head -1) || true
	if echo "$result" | grep -q "^HTTP"; then
		ok "HTTP 代理连通 Google ✓"
		echo "    Response: $result"
	else
		err "HTTP 代理无法访问 Google"
	fi
}

# --- 4. 检查 WPAD ---
test_wpad() {
	section "4. WPAD/PAC 验证"

	WPAD_URL="http://${WPAD}/wpad.dat"

	if curl -ms 5 "${WPAD_URL}" -o /dev/null -w "%{http_code}" | grep -q "200"; then
		ok "WPAD (http://${WPAD}/wpad.dat) 返回 200"
		
		wp_content=$(curl -s "${WPAD_URL}")
		line_count=$(echo "$wp_content" | wc -l)
		ok "PAC 文件有 $line_count 行规则"
		echo "    前 3 行: $(echo "$wp_content" | head -3)"
	else
		err "WPAD 不可达或返回非 200"
	fi

	# 检查 wpad.dat 是否指向正确的 HTTP 代理
	WPAD_DIR="/var/www/html/wpad/wpad.dat"
	if [ -f "$WPAD_DIR" ]; then
		if grep -q "PROXY ${WPAD}:${HTTP_PROXY_PORT}" "$WPAD_DIR" 2>/dev/null; then
			ok "PAC 文件中指向 PROXY ${WPAD}:${HTTP_PROXY_PORT}"
		elif grep -q "PROXY .*:${HTTP_PROXY_PORT}" "$WPAD_DIR" 2>/dev/null; then
			ip_in_pac=$(grep -oP 'PROXY \K[^:]+' "$WPAD_DIR" | head -1)
			ok "PAC 文件中指向 PROXY ${ip_in_pac}:${HTTP_PROXY_PORT}"
		else
			warn "PAC 文件中未找到预期的 HTTP 代理端口"
		fi
	else
		warn "PAC 文件路径 $WPAD_DIR 不存在"
	fi
}

# --- 5. DNS 解析检查 ---
test_dns() {
	section "5. DNS 解析验证"

	if dig +short "$WPAD" @localhost 2>/dev/null | grep -q '[0-9]'; then
		wp_ip=$(dig +short "$WPAD" @localhost | tail -1)
		ok "DNS 解析 wpad → $wp_ip"
	else
		err "DNS 解析 wpad 失败"
	fi

	# 检查 unbound local-zone 是否有 wpad
	unbound_check=$(unbound-control dump_cache wpad 2>/dev/null) || true
	if [ $? -eq 0 ] 2>/dev/null; then
		ok "Unbound DNS 服务正常"
	else
		warn "Unbound 控制接口可能未就绪"
	fi
}

# --- 主流程 ---
main() {
	case "${1:-all}" in
		-cfg)
			test_cfg
			;;
		-status)
			test_status
			;;
		-proxy)
			test_proxy
			;;
		-wpad)
			test_wpad
			;;
		-dns)
			test_dns
			;;
		all|-a)
			test_cfg
			test_status
			test_proxy
			test_wpad
			test_dns
			;;
		*)
			echo "用法: $0 [-v] [-cfg|-status|-proxy|-wpad|-dns|all]"
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

main "$@"
