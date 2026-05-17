#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_TEMPLATE="$ROOT_DIR/launchd/com.keyboardlanbridge.sender.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.keyboardlanbridge.sender.plist"
LOG_DIR="$HOME/Library/Logs"
APP_BASE_DIR="$HOME/Library/Application Support/KeyboardLANBridge"
APP_DIR="$APP_BASE_DIR/KeyboardLANBridgeSender.app"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_EXECUTABLE="$APP_MACOS/KeyboardLANBridgeSender"
CONFIG_SOURCE="$ROOT_DIR/configs/sender.local.json"
CONFIG_TARGET="$APP_BASE_DIR/sender.local.json"

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$APP_BASE_DIR"

swift build -c release --product sender-menubar >/dev/null

if [[ ! -f "$CONFIG_SOURCE" ]]; then
  echo "missing config: $CONFIG_SOURCE" >&2
  exit 1
fi

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$ROOT_DIR/app/KeyboardLANBridgeSender-Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/.build/release/sender-menubar" "$APP_EXECUTABLE"
cp "$CONFIG_SOURCE" "$CONFIG_TARGET"
chmod +x "$APP_EXECUTABLE"
codesign --force --deep -s - "$APP_DIR" >/dev/null 2>&1 || true

sed \
  -e "s#__ROOT__#$ROOT_DIR#g" \
  -e "s#__HOME__#$HOME#g" \
  "$PLIST_TEMPLATE" > "$PLIST_TARGET"

launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"
launchctl enable "gui/$(id -u)/com.keyboardlanbridge.sender"
launchctl kickstart -k "gui/$(id -u)/com.keyboardlanbridge.sender"

echo "installed: $PLIST_TARGET"
echo "app bundle: $APP_DIR"
echo "log: $HOME/Library/Logs/keyboard-lan-bridge-sender.log"
