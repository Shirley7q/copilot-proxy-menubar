#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/build/Copilot Proxy.app"
case "${1:-}" in
  "") APP_ARCHS=("$(uname -m)") ;;
  --universal) APP_ARCHS=(x86_64 arm64) ;;
  *) printf 'Usage: bash build.sh [--universal]\n' >&2; exit 2 ;;
esac
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
APP_BINARIES=()
for APP_ARCH in "${APP_ARCHS[@]}"; do
  APP_BINARY="$PROJECT_DIR/build/CopilotProxyMenuBar-$APP_ARCH"
  /usr/bin/swiftc -swift-version 5 -O -target "$APP_ARCH-apple-macosx13.0" \
    -framework AppKit -framework ServiceManagement \
    "$PROJECT_DIR/Sources/ProxyController.swift" "$PROJECT_DIR/Sources/main.swift" \
    -o "$APP_BINARY"
  APP_BINARIES+=("$APP_BINARY")
done
/usr/bin/lipo -create "${APP_BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/CopilotProxyMenuBar"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/bin/swift "$PROJECT_DIR/Sources/Icon.swift" "$PROJECT_DIR/build"
/usr/bin/iconutil -c icns "$PROJECT_DIR/build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/lipo -info "$APP_DIR/Contents/MacOS/CopilotProxyMenuBar"
printf '%s\n' "$APP_DIR"
