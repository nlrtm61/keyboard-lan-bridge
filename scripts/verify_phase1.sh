#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d)"
CONFIG_PATH="$TMP_DIR/receiver.test.json"
LOG_PATH="$TMP_DIR/receiver.log"
PORT=8877
TOKEN="phase1-test-token"

cat > "$CONFIG_PATH" <<JSON
{
  "bindHost": "127.0.0.1",
  "port": $PORT,
  "sharedToken": "$TOKEN",
  "allowedSourceIPs": ["127.0.0.1"],
  "promptForPermissionsOnLaunch": false,
  "logRequests": true
}
JSON

swift build >/dev/null
./.build/debug/receiver run --config "$CONFIG_PATH" --dry-run >"$LOG_PATH" 2>&1 &
RECEIVER_PID=$!

cleanup() {
  kill "$RECEIVER_PID" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

sleep 2

echo "== health =="
curl --fail --silent "http://127.0.0.1:$PORT/health"
echo
echo

echo "== valid key =="
curl --fail --silent -X POST "http://127.0.0.1:$PORT/v1/key" \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"key\":\"space\",\"action\":\"tap\"}"
echo
echo

echo "== invalid token (expect 401) =="
curl --silent -o /dev/null -w '%{http_code}\n' -X POST "http://127.0.0.1:$PORT/v1/key" \
  -H 'Content-Type: application/json' \
  -d '{"token":"wrong","key":"space","action":"tap"}'

echo "== invalid key (expect 422) =="
curl --silent -o /dev/null -w '%{http_code}\n' -X POST "http://127.0.0.1:$PORT/v1/key" \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"key\":\"rm-rf\",\"action\":\"tap\"}"

echo "== disable receiver =="
curl --fail --silent -X POST "http://127.0.0.1:$PORT/v1/control/disable" \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\"}"
echo
echo

echo "== send while disabled (expect 409) =="
curl --silent -o /dev/null -w '%{http_code}\n' -X POST "http://127.0.0.1:$PORT/v1/key" \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"key\":\"enter\",\"action\":\"tap\"}"

echo "== enable receiver =="
curl --fail --silent -X POST "http://127.0.0.1:$PORT/v1/control/enable" \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\"}"
echo
echo

echo "== sender manual send =="
SENDER_CONFIG="$TMP_DIR/sender.test.json"
cat > "$SENDER_CONFIG" <<JSON
{
  "receiverHost": "127.0.0.1",
  "receiverPort": $PORT,
  "sharedToken": "$TOKEN",
  "promptForPermissionsOnLaunch": false,
  "enabledOnLaunch": true,
  "toggleHotkey": "f18",
  "quitHotkey": "f19",
  "logNetworkResponses": true,
  "hotkeys": []
}
JSON
./.build/debug/sender send --config "$SENDER_CONFIG" --key right-arrow
echo
echo

echo "== receiver log =="
cat "$LOG_PATH"
