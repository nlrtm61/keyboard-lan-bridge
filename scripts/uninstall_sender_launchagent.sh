#!/bin/zsh
set -euo pipefail

PLIST_TARGET="$HOME/Library/LaunchAgents/com.keyboardlanbridge.sender.plist"
APP_DIR="$HOME/Library/Application Support/KeyboardLANBridge/KeyboardLANBridgeSender.app"

launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
rm -f "$PLIST_TARGET"

echo "removed: $PLIST_TARGET"
echo "app bundle kept: $APP_DIR"
