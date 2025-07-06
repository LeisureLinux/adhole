#!/bin/bash
set -e
# set -x
# Monitor proxy status
# We have two local socks5(ShadowSocks) proxy service running on tcp port 2023 and 2026(For my own usage with IPv6).
# http://wpad is a local web server hosting the pac script: wpad.dat, which tell the proxy server rules.
# Global Variable to modify
WPAD="wpad"
[ -n "$2" ] && WPAD="$2"
WPAD_IP=$(getent hosts $WPAD 2>/dev/null | awk '{print $1}')
# WPAD_IP=$(dig -tA +short wpad)
[ -z "$WPAD_IP" ] && echo "Error: not able to resolve wpad hostname: $WPAD" && exit
#
WPAD_URL="http://$WPAD/wpad.dat"
P4="socks5h://$WPAD:2023"
P6="socks5h://$WPAD:2026"
#
CHECK_URL="https://www.google.com/"
SSH_OPTION="-o StrictHostKeyChecking=accept-new"

check_ip() {
  if ping -qc1 "${WPAD_IP}" 1>/dev/null 2>/dev/null; then
    return
  else
    echo "Error: ping ${WPAD_IP} failed."
    exit 1
  fi
}
#
check4() {
  echo "Info: Checking IPv4 availability ..."
  if ! dig -tA +short $WPAD >/dev/null; then
    echo "Error: Not able to resolv IPv4 hostname: wpad"
    exit 1
  fi
  if ! ping -4 -q -c 2 $WPAD >/dev/null 2>&1; then
    echo "Error: Not able to ping wpad IPv4 address"
    exit 1
  fi
  if [ "$(curl -4 -q -kIsS "$WPAD_URL" -w "%{http_code}" -o /dev/null)" != "200" ]; then
    echo "Error: curl IPv4 $WPAD_URL failed."
    exit 2
  else
    echo "Info: curl v4 wpad.dat is OK."
  fi

  get_port "$P4"
  if ! nc -4zv "$WPAD" "$port" >/dev/null 2>&1; then
    echo "Error: Check port $port failed."
    exit 3
  else
    echo "Info: port $port is OK."
  fi

  ssh -4 "$SSH_OPTION" "wpad" "echo Info: SSH to wpad on IPv4 is OK" || echo "Error: SSH to wpad IPv4 failed."

  echo "Info: Checking proxy: $P4 ..."
  if ! curl -q -4 -x $P4 -kIsS $CHECK_URL 2>/dev/null | grep -q "^HTTP"; then
    fail=4
    echo "Error: Using $P4 to access IPv4 failed."
  else
    echo "Info: Proxy $P4 is OK."
  fi
  echo
}
# Network level check SS tcp port open
#
check6() {
  echo "Info: Checking IPv6 availability ..."
  if [ "$(cat /sys/module/ipv6/parameters/disable)" = "1" ]; then
    echo "Error: IPv6 disabled in OS!"
    return
  fi
  if ! dig -tAAAA +short $WPAD >/dev/null; then
    echo "Error: Not able to resolv IPv6 hostname: wpad"
    exit 1
  fi
  if ! ping -6 -q -c 2 $WPAD 1>/dev/null 2>&1; then
    echo "Error: Not able to ping wpad IPv6 address"
    exit 1
  fi
  if ! curl -6 -q -kIsS $WPAD_URL | grep ^HTTP | grep -q -w 200; then
    echo "Error: curl IPv6 $WPAD_URL failed."
    exit 2
  else
    echo "Info: curl v6 wpad.dat is OK."
  fi
  get_port $P6
  if ! nc -6zv $WPAD "$port" >/dev/null 2>&1; then
    echo "Error: Check port $port failed."
    exit 3
  else
    echo "Info: port $port is OK."
  fi
  ssh -6 "$SSH_OPTION" $WPAD "echo Info: SSH to wpad on IPv6 is OK" || echo "Error: SSH to wpad IPv6 failed."
  # Application level check SS is working
  echo "Info: Checking proxy: $P6 ..."
  if ! curl -q -6 -x $P6 -kIsS $CHECK_URL 2>/dev/null | grep -q "^HTTP"; then
    fail=6
    echo "Error: Using $P6 to access IPv6 failed."
  else
    echo "Info: Proxy $P6 is OK."
  fi
  echo
}

get_port() {
  port=1080
  # port="$(echo "$1" | sed 's|\(.*\):\(.*\):\(.*\)|\3|')"
  port="$(echo "$1" | awk -F: '{print $3}')"
  return
}

# Main Prog.
#
# check related package installed
if ! hash dig curl nc; then
  echo "Error: Missing dig,hash,nc command in PATH."
  exit 9
fi
check_ip
[ "$1" = "-4" ] && check4
[ "$1" = "-6" ] && check6
[ -z "$1" ] && check4 && check6
#
[ -z "$fail" ] && echo "All is well."
