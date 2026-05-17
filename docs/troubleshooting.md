# Troubleshooting

## キーが発火しない

- 受信側で `receiver permissions --prompt` を実行してください
- `/health` の `readyForPosting` を確認してください
- フルスクリーンアプリやセキュア入力の影響を疑ってください

## sender がホットキーを拾わない

- 送信側で `sender permissions --prompt` を実行してください
- `Shift+Escape` で `LOCAL` / `REMOTE` が切り替わるか確認してください
- 一度 Terminal 前面で `sender-menubar` を起動して挙動を確認してください

## 401 / 403 が返る

- `401`: トークン不一致
- `403`: `allowedSourceIPs` に送信元 IP が入っていない

## 暴走が怖い

- `Shift+Escape` で `LOCAL` に戻せます
- `F19` で送信側を終了できます
- 受信側へ `POST /v1/control/disable` を送れば注入を止められます

## CapsLock が期待どおりに切り替わらない

- `preferredJapaneseInputSourceID`
- `preferredLatinInputSourceID`

上記を `receiver.local.json` で明示してください。
