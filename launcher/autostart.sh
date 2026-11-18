#!/bin/bash
# One-time installation (or removal) explicitly authorized from the AG menu.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

label=local.antigravity.proxy-launcher.relay
service="system/$label"
helper_root=/Library/PrivilegedHelperTools
job_root=/Library/LaunchDaemons
installed="$helper_root/$label"
plist="$job_root/$label.plist"
resources="$(cd "$(dirname "$0")" && pwd)"
bundled_runtime="$resources/proxy-runtime.sh"
bundled_relay="$resources/antigravity-relay"

fail() { echo "$*" >&2; exit 1; }

require_protected_directory() {
  local directory="$1" mode
  [ ! -L "$directory" ] && [ -d "$directory" ] && [ "$(stat -f %u "$directory")" = 0 ] ||
    fail "系统服务目录的所有者或类型不正确：$directory"
  mode="$(stat -f %Lp "$directory")"
  (( (8#$mode & 022) == 0 )) || fail "系统服务目录不能允许其他用户写入：$directory"
}

stop_job() {
  if launchctl print "$service" >/dev/null 2>&1; then
    launchctl bootout "$service"
  fi
}

[ "$EUID" -eq 0 ] || fail "设置代理自启动需要管理员权限。"
case "${1:-}" in
  enable|disable) action="$1" ;;
  *) fail "用法：autostart.sh enable <代理 IPv4> <端口> 或 autostart.sh disable" ;;
esac

if [ ! -e "$helper_root" ] && [ ! -L "$helper_root" ]; then
  install -d -o root -g wheel -m 755 "$helper_root"
fi
require_protected_directory "$helper_root"
require_protected_directory "$job_root"
lock="$helper_root/.$label.lock"
shlock -f "$lock" -p "$$" || fail "另一项自启动设置正在进行，请稍后再试。"
trap 'rm -f "$lock"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

if [ "$action" = disable ]; then
  stop_job || fail "无法停止代理自启动服务。"
  rm -f "$plist"
  /bin/bash "$bundled_runtime" cleanup
  if [ -e "$installed" ] || [ -L "$installed" ]; then
    require_protected_directory "$installed"
    rm -f "$installed/proxy-runtime.sh" "$installed/antigravity-relay" "$installed/service.log"
    rmdir "$installed"
  fi
  echo "已停用代理自启动。"
  exit 0
fi

proxy_host="${2:-}"
proxy_port="${3:-}"
/bin/bash "$bundled_runtime" check-autostart "$bundled_relay" "$proxy_host" "$proxy_port"
if [ ! -e "$installed" ] && [ ! -L "$installed" ]; then
  install -d -o root -g wheel -m 755 "$installed"
fi
require_protected_directory "$installed"

stage="$(mktemp -d "$installed/.install.XXXXXX")"
finish_install() {
  local result=$?
  trap - EXIT
  if [ "$result" -ne 0 ] && [ "$replacing" -eq 1 ]; then
    stop_job || true
    rm -f "$plist"
    /bin/bash "$bundled_runtime" cleanup || true
  fi
  rm -rf "$stage"
  rm -f "$lock"
  exit "$result"
}
replacing=0
trap finish_install EXIT

# Publish the new files only after staging and validating the complete job.
install -o root -g wheel -m 755 "$bundled_runtime" "$stage/proxy-runtime.sh"
install -o root -g wheel -m 755 "$bundled_relay" "$stage/antigravity-relay"
cat > "$stage/job.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$installed/proxy-runtime.sh</string>
    <string>watch</string>
    <string>$installed/antigravity-relay</string>
    <string>$proxy_host</string>
    <string>$proxy_port</string>
  </array>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>15</integer>
  <key>StandardOutPath</key><string>$installed/service.log</string>
  <key>StandardErrorPath</key><string>$installed/service.log</string>
</dict>
</plist>
PLIST
plutil -lint "$stage/job.plist" >/dev/null

stop_job || fail "无法停止代理自启动服务。"
replacing=1
/bin/bash "$bundled_runtime" cleanup
mv -f "$stage/proxy-runtime.sh" "$installed/proxy-runtime.sh"
mv -f "$stage/antigravity-relay" "$installed/antigravity-relay"
if [ ! -e "$installed/service.log" ]; then
  install -o root -g wheel -m 644 /dev/null "$installed/service.log"
fi
install -o root -g wheel -m 644 "$stage/job.plist" "$plist"
launchctl enable "$service"
launchctl bootstrap system "$plist"
echo "已启用代理自启动。后台服务会等待 SOCKS5 与中继通过 HTTPS 检测。"
