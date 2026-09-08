#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
APP_NAME="CopilotProxyMenuBar-v$APP_VERSION-macos-universal"
APP_DIR="$PROJECT_DIR/build/Copilot Proxy.app"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copilot-menubar-release.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
bash "$PROJECT_DIR/build.sh" --universal
mkdir -p "$DIST_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Copilot Proxy.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/docs/INSTALL.txt" "$STAGING_DIR/安装说明.txt"
hdiutil create -volname 'Copilot Proxy' -srcfolder "$STAGING_DIR" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/$APP_NAME.zip"
(
  cd "$DIST_DIR"
  shasum -a 256 "$APP_NAME.dmg" "$APP_NAME.zip" > SHA256SUMS.txt
)
printf 'Release files: %s\n' "$DIST_DIR"
