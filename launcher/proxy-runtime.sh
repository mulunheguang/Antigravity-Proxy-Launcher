#!/bin/bash
# Called by the native launcher and the optional launchd job.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH ALL_PROXY HTTP_PROXY HTTPS_PROXY
unset all_proxy http_proxy https_proxy
STATE=/var/run/antigravity-proxy-launcher
MARKER='# antigravity-proxy-launcher'
TEST_URL=https://www.googleapis.com/
CHECK_INTERVAL=15
MAX_FAILURES=3
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
  local pid="${1:-}" process status executable
  if [ -z "$pid" ]; then
    [ -f "$STATE/pid" ] || return 1
    pid="$(cat "$STATE/pid")"
  fi
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ "$pid" -gt 1 ] || return 1
  process="$(ps -p "$pid" -o stat= -o comm= 2>/dev/null)" || return 1
  read -r status executable <<< "$process"
  [[ "$status" != Z* && "$executable" = "$STATE/relay" ]]
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

wait_for_relay_exit() {
  local pid="$1" attempt
  for attempt in {1..30}; do
    relay_running "$pid" || return 0
    sleep .1
  done
  ! relay_running "$pid"
}

stop_owned_relay() {
  if relay_running; then
    local pid
    pid="$(cat "$STATE/pid")"
    if ! kill -TERM "$pid" 2>/dev/null && relay_running "$pid"; then
      fail "无法向本启动器的中继发送退出信号。"
    fi
    if ! wait_for_relay_exit "$pid"; then
      # Older relays may have inherited SIGTERM as ignored from the launching shell.
      # Recheck the captured PID and executable before escalating.
      if relay_running "$pid" && ! kill -KILL "$pid" 2>/dev/null && relay_running "$pid"; then
        fail "无法结束本启动器的中继。"
      fi
      wait_for_relay_exit "$pid" || fail "中继尚未退出，请稍后重试。"
    fi
  fi
  rm -f "$STATE/pid" "$STATE/upstream"
}

has_owned_hosts() {
  awk -v marker="$MARKER" '
    { sub(/[[:space:]]+$/, "") }
    $1 == "127.0.0.1" && substr($0, length($0)-length(marker)+1) == marker { found=1 }
    END { exit !found }
  ' /etc/hosts
}

remove_hosts() {
  has_owned_hosts || return 0
  local temporary
  temporary="$(mktemp /etc/antigravity-launcher-hosts.XXXXXX)"
  if ! awk -v marker="$MARKER" '
    { line=$0; sub(/[[:space:]]+$/, "", line) }
    $1 != "127.0.0.1" || substr(line, length(line)-length(marker)+1) != marker
  ' /etc/hosts >"$temporary" || ! cat "$temporary" > /etc/hosts; then
    rm -f "$temporary"
    return 1
  fi
  rm -f "$temporary"
  flush_dns
}

flush_dns() {
  dscacheutil -flushcache 2>/dev/null || true
  killall -HUP mDNSResponder 2>/dev/null || true
}

validate_settings() {
  [[ "$proxy_host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || fail "代理地址应为 IPv4。"
  local octets octet
  IFS=. read -r -a octets <<< "$proxy_host"
  for octet in "${octets[@]}"; do
    [[ "$octet" = 0 || "$octet" != 0* ]] && [ "$octet" -le 255 ] || fail "代理地址应为 IPv4。"
  done
  [[ "$proxy_port" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$proxy_port" -le 65535 ] || fail "代理端口不正确。"
  [ -f "$relay" ] && [ -x "$relay" ] || fail "启动器缺少可执行的中继。"
}

probe_https() {
  curl --disable "$@" --connect-timeout 5 --max-time 15 --silent --show-error \
    --output /dev/null "$TEST_URL"
}

probe_relay() {
  probe_https --noproxy '*' --resolve 'www.googleapis.com:443:127.0.0.1'
}

check_foreign_hosts() {
  local conflicts
  conflicts="$(awk -v marker="$MARKER" -v domains="${DOMAINS[*]}" '
    BEGIN { count=split(domains, names, " "); for (i=1; i<=count; i++) tracked[names[i]]=1 }
    {
      line=$0; sub(/[[:space:]]+$/, "", line)
      if ($1 == "127.0.0.1" && substr(line, length(line)-length(marker)+1) == marker) next
      sub(/#.*/, "")
      for (i=2; i<=NF; i++) if (tolower($i) in tracked) print $i
    }
  ' /etc/hosts | sort -u)"
  [ -z "$conflicts" ] || fail "hosts 已有其他来源的域名映射。请先在旧版代理中清理 hosts 与中继，再启用自启动：
$conflicts"
}

run_runtime() {
  /bin/bash "$0" "$1" "$relay" "$proxy_host" "$proxy_port"
}

watch_proxy() {
  local failures=0 report='' last_report='' details
  trap 'exit 0' INT TERM
  trap 'run_runtime cleanup' EXIT
  while true; do
    if ready; then
      if details="$(probe_relay 2>&1)"; then
        failures=0
        report='中继已就绪，可通过原版 Antigravity 图标打开应用。'
      else
        failures=$((failures + 1))
        report="中继 HTTPS 检测失败（${failures}/${MAX_FAILURES}）：$details"
        if [ "$failures" -ge "$MAX_FAILURES" ]; then
          if details="$(run_runtime cleanup 2>&1)"; then
            report='中继连续检测失败，已撤销本启动器的 hosts 映射，等待恢复。'
          else
            report="清理失败，将重试：$details"
          fi
        fi
      fi
    else
      failures=0
      # Stale mappings after a crash or reboot must be removed even if the upstream is down.
      if { has_owned_hosts || [ -f "$STATE/pid" ]; } && ! details="$(run_runtime cleanup 2>&1)"; then
        report="清理旧代理环境失败，将重试：$details"
      elif ! details="$(probe_https --noproxy '' --proxy "socks5h://$proxy_host:$proxy_port" 2>&1)"; then
        report="等待 SOCKS5 上游通过 HTTPS 检测：$details"
      elif details="$(run_runtime prepare-auto 2>&1)"; then
        report='中继已就绪，可通过原版 Antigravity 图标打开应用。'
      else
        report="准备代理失败，将重试：$details"
      fi
    fi
    if [ "$report" != "$last_report" ]; then
      printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$report"
      last_report="$report"
    fi
    sleep "$CHECK_INTERVAL" & wait $! || true
  done
}

check_state
case "$action" in
  status) ready; exit $? ;;
  verify) ready && probe_relay; exit $? ;;
  check-autostart) validate_settings; check_foreign_hosts; exit $? ;;
  watch|prepare|prepare-auto|cleanup) [ "$EUID" -eq 0 ] || fail "此操作需要管理员权限。" ;;
  *) fail "用法: proxy-runtime.sh status|verify|prepare|cleanup <relay> <proxy IPv4> <proxy port>" ;;
esac

if [ "$action" = watch ]; then
  validate_settings
  watch_proxy
  exit 0
fi

mkdir -p "$STATE"
chmod 755 "$STATE"
# shlock replaces a lock whose owning process died and serializes new runtime instances.
lock="$STATE/runtime.lock"
for attempt in {1..50}; do
  if shlock -f "$lock" -p "$$"; then break; fi
  sleep .1
done
[ -f "$lock" ] && [ "$(cat "$lock")" -eq "$$" ] || fail "另一个代理操作正在进行，请稍后重试。"
trap 'rm -f "$lock"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

if [ "$action" = cleanup ]; then
  remove_hosts
  stop_owned_relay
  echo "已停止启动器中继，并移除它添加的 hosts 记录。"
  exit 0
fi

validate_settings
if [ "$action" = prepare-auto ]; then check_foreign_hosts; fi

if ready && probe_relay; then
  echo "代理环境已就绪。"
  exit 0
fi

remove_hosts
stop_owned_relay
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
  remove_hosts || true
  stop_owned_relay || true
  rm -f "$lock"
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
probe_relay || fail "中继的 HTTPS 转发校验失败。"

for domain in "${DOMAINS[@]}"; do
  printf '127.0.0.1 %s %s\n' "$domain" "$MARKER" >> /etc/hosts
done
printf '%s:%s\n' "$proxy_host" "$proxy_port" > "$STATE/upstream"
chmod 644 "$STATE/upstream"
flush_dns
ready || fail "中继启动后的状态校验失败。"
trap 'rm -f "$lock"' EXIT
echo "中继及域名映射已就绪。"
