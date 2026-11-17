#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target_app="${1:-/Applications/Antigravity.app}"
output="$root/dist/Antigravity Launcher.app"
architecture="$(uname -m)"
minimum_system=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$root/launcher/Info.plist")
build_target="${architecture}-apple-macos${minimum_system}"

[ -d "$target_app" ] || { echo "找不到目标应用: $target_app" >&2; exit 1; }
[ "$architecture" = arm64 ] || { echo "当前构建脚本要求 Apple Silicon Mac。" >&2; exit 1; }
app_icon=$(/usr/bin/plutil -extract CFBundleIconFile raw "$target_app/Contents/Info.plist")
case "$app_icon" in *.icns) ;; *) app_icon="$app_icon.icns" ;; esac
[ -f "$target_app/Contents/Resources/$app_icon" ] || { echo "找不到应用图标。" >&2; exit 1; }

mkdir -p "$root/dist" "$root/.build/module-cache"
temporary="$(mktemp -d "$root/dist/.launcher-build.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
app="$temporary/Antigravity Launcher.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

xcrun swiftc -target "$build_target" -swift-version 5 -O \
  -module-cache-path "$root/.build/module-cache" \
  -framework AppKit "$root/launcher/Launcher.swift" \
  -o "$app/Contents/MacOS/AntigravityProxyLauncher"
xcrun clang -target "$build_target" -Wall -Wextra -O2 -pthread \
  "$root/src/relay.c" -o "$app/Contents/Resources/antigravity-relay"

# Verify Mach-O deployment targets before publishing the application bundle.
for binary in "$app/Contents/MacOS/AntigravityProxyLauncher" "$app/Contents/Resources/antigravity-relay"; do
  actual_minimum=$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }')
  if [ "$actual_minimum" != "$minimum_system" ]; then
    echo "最低系统版本不一致: $binary ($actual_minimum，期望 $minimum_system)" >&2
    exit 1
  fi
done

cp "$root/launcher/Info.plist" "$app/Contents/Info.plist"
cp "$root/launcher/config.json" "$root/launcher/proxy-runtime.sh" "$app/Contents/Resources/"
cp "$target_app/Contents/Resources/$app_icon" "$app/Contents/Resources/Antigravity.icns"
chmod 755 "$app/Contents/MacOS/AntigravityProxyLauncher" \
  "$app/Contents/Resources/proxy-runtime.sh" "$app/Contents/Resources/antigravity-relay"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app/Contents/Resources/antigravity-relay"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
rm -rf "$output"
mv "$app" "$output"
printf '已生成 %s\n' "$output"
