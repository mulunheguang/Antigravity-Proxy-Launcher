#!/bin/bash
# Called by the native launcher. Only prepare/cleanup require administrator rights.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH ALL_PROXY HTTP_PROXY HTTPS_PROXY
STATE=/var/run/antigravity-proxy-launcher
MARKER='# antigravity-proxy-launcher'
DOMAINS=(
  daily-cloudcode-pa.googleapis.com cloudcode-pa.googleapis.com oauth2.googleapis.com
  accounts.google.com www.googleapis.com generativelanguage.googleapis.com
  content-cloudcode-pa.googleapis.com
)
action="${1:-}"
relay="${2:-}"
proxy_host="${3:-}"
proxy_port="${4:-}"

fail() { echo "$*" >&2; exit 1; }

check_state() {
  [ ! -L "$STATE" ] || fail "中继状态目录不能是符号链接。"
  if [ -e "$STATE" ]; then
    [ -d "$STATE" ] && [ "$(stat -f %u "$STATE")" = 0 ] &&
      [ "$(stat -f %Lp "$STATE")" = 755 ] || fail "中继状态目录的所有者或权限不正确。"
  fi
}

relay_running() {
  [ -f "$STATE/pid" ] || return 1
  local pid
  pid="$(cat "$STATE/pid")"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ "$pid" -gt 1 ] || return 1
  [ "$(ps -p "$pid" -o comm= 2>/dev/null)" = "$STATE/relay" ]
}

hosts_ready() {
  local domain
  for domain in "${DOMAINS[@]}"; do
    awk -v domain="$domain" '
      $1 == "127.0.0.1" { for (i=2; i<=NF && $i != "#"; i++) if ($i == domain) found=1 }
      END { exit !found }
    ' /etc/hosts || return 1
  done
}

ready() {
  check_state
  [ -f "$STATE/upstream" ] || return 1
  [ "$(cat "$STATE/upstream")" = "$proxy_host:$proxy_port" ] || return 1
  cmp -s "$relay" "$STATE/relay" || return 1
  relay_running && hosts_ready
}

stop_owned_relay() {
  if relay_running; then
    local pid attempt
    pid="$(cat "$STATE/pid")"
    kill "$pid"
    for attempt in {1..30}; do
      relay_running || break
      sleep .1
    done
    if relay_running; then fail "中继尚未退出，请稍后重试。"; fi
  fi
  rm -f "$STATE/pid" "$STATE/upstream"
}

remove_hosts() {
  local temporary
  temporary="$(mktemp /etc/antigravity-launcher-hosts.XXXXXX)"
  if ! awk -v marker="$MARKER" 'index($0, marker) == 0' /etc/hosts >"$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  cat "$temporary" > /etc/hosts
  rm -f "$temporary"
}

flush_dns() {
  dscacheutil -flushcache 2>/dev/null || true
  killall -HUP mDNSResponder 2>/dev/null || true
}

check_state
case "$action" in
  status) ready; exit $? ;;
  prepare|cleanup) [ "$EUID" -eq 0 ] || fail "此操作需要管理员权限。" ;;
  *) fail "用法: proxy-runtime.sh status|prepare|cleanup <relay> <proxy IPv4> <proxy port>" ;;
esac

mkdir -p "$STATE"
chmod 755 "$STATE"
mkdir "$STATE/lock" 2>/dev/null || fail "另一个代理操作正在进行，请稍后重试。"
trap 'rmdir "$STATE/lock" 2>/dev/null || true' EXIT

if [ "$action" = cleanup ]; then
  stop_owned_relay
  remove_hosts
  flush_dns
  echo "已停止启动器中继，并移除它添加的 hosts 记录。"
  exit 0
fi

[[ "$proxy_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "代理地址应为 IPv4。"
[[ "$proxy_port" =~ ^[0-9]+$ ]] && [ "$proxy_port" -ge 1 ] &&
  [ "$proxy_port" -le 65535 ] || fail "代理端口不正确。"
[ -f "$relay" ] && [ -x "$relay" ] || fail "启动器缺少可执行的中继。"

if ready; then
  echo "代理环境已就绪。"
  exit 0
fi

stop_owned_relay
remove_hosts
flush_dns
if lsof -nP -iTCP:443 -sTCP:LISTEN -t >/dev/null 2>&1; then
  fail "本机 443 端口已被其他程序占用。请先停止旧版代理或占用该端口的服务。"
fi

for domain in "${DOMAINS[@]}"; do
  if ! awk -v domain="$domain" '
    $1 !~ /^#/ && NF > 1 && $1 != "127.0.0.1" {
      for (i=2; i<=NF && $i != "#"; i++) if ($i == domain) conflict=1
    }
    END { exit conflict }
  ' /etc/hosts; then
    fail "hosts 中已有 $domain 的其他地址配置，请先检查该记录。"
  fi
done

# Roll back the new listener and mappings if any preparation step fails.
rollback() {
  local result=$?
  trap - EXIT
  stop_owned_relay || true
  remove_hosts || true
  flush_dns
  rmdir "$STATE/lock" 2>/dev/null || true
  exit "$result"
}
trap rollback EXIT
install -o root -g wheel -m 755 "$relay" "$STATE/relay.new"
mv -f "$STATE/relay.new" "$STATE/relay"
: > "$STATE/relay.log"
chmod 644 "$STATE/relay.log"
# AppleScript administrator sessions have no console for macOS nohup to detach.
# Ignore SIGHUP in a subshell, then exec so $! remains the relay PID.
(
  trap '' HUP
  exec "$STATE/relay" 443 "$proxy_host" "$proxy_port"
) </dev/null >>"$STATE/relay.log" 2>&1 &
echo $! > "$STATE/pid"
chmod 644 "$STATE/pid"
# Wait for bind/listen rather than assuming a newly copied executable starts in 300 ms.
for attempt in {1..100}; do
  if grep -q 'listening on 127.0.0.1:' "$STATE/relay.log"; then
    break
  fi
  relay_running || break
  sleep .1
done
if ! relay_running || ! grep -q 'listening on 127.0.0.1:' "$STATE/relay.log"; then
  cat "$STATE/relay.log" >&2
  fail "中继启动失败，日志位于 $STATE/relay.log。"
fi

# A complete SOCKS5 tunnel, TLS certificate verification and HTTPS response are required.
curl --noproxy '*' --resolve 'www.googleapis.com:443:127.0.0.1' \
  --connect-timeout 5 --max-time 15 --silent --show-error --output /dev/null \
  https://www.googleapis.com/ || fail "中继的 HTTPS 转发校验失败。"

for domain in "${DOMAINS[@]}"; do
  printf '127.0.0.1 %s %s\n' "$domain" "$MARKER" >> /etc/hosts
done
printf '%s:%s\n' "$proxy_host" "$proxy_port" > "$STATE/upstream"
chmod 644 "$STATE/upstream"
flush_dns
ready || fail "中继启动后的状态校验失败。"
trap 'rmdir "$STATE/lock" 2>/dev/null || true' EXIT
echo "中继及域名映射已就绪。"
