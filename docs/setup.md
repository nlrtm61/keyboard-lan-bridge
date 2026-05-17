# Setup

## 想定構成

- 送信側Mac: 実キーボードがつながっているMac
- 受信側Mac: 入力を受け取るMac
- 同一LAN内で接続

## 1. ビルド

```bash
swift build -c release
```

## 2. 設定ファイル作成

受信側:

```bash
cp ./configs/receiver.sample.json ./configs/receiver.local.json
```

送信側:

```bash
cp ./configs/sender.sample.json ./configs/sender.local.json
```

## 3. 設定値

- `sharedToken`: 送受信で共通のランダム文字列
- `receiverHost`: 受信側Macの LAN IP
- `allowedSourceIPs`: 送信側Macの LAN IP
- `bindHost`: 通常は `0.0.0.0`
- `enabledOnLaunch`: 最初は `false` 推奨

## 4. 起動

受信側:

```bash
.build/release/receiver run --config ./configs/receiver.local.json
```

送信側:

```bash
.build/release/sender run --config ./configs/sender.local.json
```

または:

```bash
.build/release/sender-menubar --config ./configs/sender.local.json
```

## 5. 権限付与

必要権限の詳細は [permissions.md](permissions.md) を参照してください。

確認コマンド:

```bash
.build/release/receiver permissions --prompt
.build/release/sender permissions --prompt
```

## 6. 動作確認

ヘルスチェック:

```bash
curl http://RECEIVER_IP:8765/health
```

手動送信:

```bash
.build/release/sender send --config ./configs/sender.local.json --key space
```

## 7. Big Sur での注意

- 最低対象は macOS 11
- 受信側が古い Intel Mac の場合、その実機で `swift build` したほうが安全です
- 未署名バイナリ運用では、権限再付与が必要になることがあります
