# keyboard-lan-bridge

同一LAN内の2台のMacのあいだで、キーボード入力だけを片方向転送するための macOS 向け実験的プロジェクトです。

想定ユースケース:

- 手元のメインMacで入力する
- 少し古いサブMacを横に置いて使う
- キーボードのBluetooth切替や2台運用の煩雑さを減らす

このプロジェクトは、送信元Macのキーボードイベントを LAN 内で送信し、受信先Macで `CGEvent` として再現します。対象を「キーボードのみ」「LAN内のみ」「MacからMacへの片方向入力」に絞ることで、古い macOS 環境でも現実的に動かせることを狙っています。

## なぜ作ったのか

背景は [docs/why-this-project.md](docs/why-this-project.md) にまとめていますが、要点は次のとおりです。

- Apple純正の Universal Control は対応OSと対応ハードウェアに制約がある
- 古い Intel Mac や Big Sur 環境では使えないケースがある
- Barrier / Input Leap 系は高機能だが、macOS 権限、修飾キー、古い環境での安定性調整が重い
- 今回ほしかったのは「画面共有」でも「マウス共有」でもなく「キーボードだけを確実に送る」ことだった

## できること

- 送信側 `sender` でキーボード入力を監視
- `Shift+Escape` で `LOCAL` / `REMOTE` を切替
- 受信側 `receiver` で HTTP 経由のキーイベントを受信
- トークン認証と送信元 IP 制限
- `CapsLock` を受信側の日本語/英字入力切替に使う設定
- LaunchAgent による常駐起動
- メニューバーアプリ `sender-menubar` による状態表示

## まだ弱いところ

- 実験的実装です
- IME 状態の完全同期はしません
- JIS/US 配列差は一部未吸収です
- マウス共有、クリップボード共有、双方向制御は対象外です

## 動作要件

- macOS 11 以上
- Swift 5.5 以上
- 送信側/受信側ともに macOS の Accessibility 系権限が必要

Big Sur 向けの注意点は [docs/setup.md](docs/setup.md) に記載しています。

## リポジトリ構成

- `Sources/KeyboardLANBridgeCore`: 共通ロジック
- `Sources/sender`: 送信側 CLI
- `Sources/receiver`: 受信側 CLI
- `Sources/sender-menubar`: 送信側メニューバーアプリ
- `configs`: サンプル設定
- `scripts`: LaunchAgent インストール補助
- `docs`: セットアップ、権限、公開手順など

## ビルド

```bash
swift build -c release
```

生成物:

- `.build/release/receiver`
- `.build/release/sender`
- `.build/release/sender-menubar`

## 最短セットアップ

1. 受信側Macで `configs/receiver.sample.json` を `receiver.local.json` として複製する
2. 送信側Macで `configs/sender.sample.json` を `sender.local.json` として複製する
3. 両方の `sharedToken` を同じランダム文字列にする
4. `receiverHost` に受信側Macの LAN IP を入れる
5. `allowedSourceIPs` に送信側Macの LAN IP を入れる
6. 受信側で `receiver` を起動する
7. 送信側で `sender-menubar` または `sender` を起動する
8. 権限を付与し、`Shift+Escape` で `REMOTE` に切り替える

詳細は [docs/setup.md](docs/setup.md) を参照してください。

## 起動例

受信側:

```bash
cp ./configs/receiver.sample.json ./configs/receiver.local.json
.build/release/receiver run --config ./configs/receiver.local.json
```

送信側 CLI:

```bash
cp ./configs/sender.sample.json ./configs/sender.local.json
.build/release/sender run --config ./configs/sender.local.json
```

送信側メニューバー:

```bash
.build/release/sender-menubar --config ./configs/sender.local.json
```

## 操作方法

- `Shift+Escape`: `LOCAL` / `REMOTE` 切替
- `LOCAL`: 送信側Macだけに入力
- `REMOTE`: 受信側Macだけに入力
- `F19`: `sender` プロセスの終了

ホットキー例は `configs/sender.sample.json` に含まれています。

## セキュリティ方針

- 公開インターネット用途ではなく、家庭内・社内など信頼できる LAN を前提としています
- 共有トークンで認証します
- `allowedSourceIPs` で送信元を制限します
- 任意コマンド実行機能は持ちません

詳細は [SECURITY.md](SECURITY.md) を参照してください。

## 公開前に除外すべきもの

このリポジトリへは次を含めないでください。

- `configs/*.local.json`
- `.build/`
- `*.dSYM`
- ログ
- 個人の LAN IP、ホスト名、ユーザー名、絶対パス

この公開用フォルダでは、上記を除外した前提で整理しています。

## GitHub への上げ方

[docs/github-publish.md](docs/github-publish.md) に、リポジトリ作成から push までの手順を書いてあります。

## コントリビュート

改善提案や不具合報告は歓迎です。事前に [CONTRIBUTING.md](CONTRIBUTING.md) を確認してください。

## ライセンス

[MIT License](LICENSE)
