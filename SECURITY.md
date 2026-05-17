# Security

## Intended Scope

このプロジェクトは信頼できる LAN 内での利用を前提としています。公開インターネットへ露出する前提では設計していません。

## Current Controls

- 共有トークンによる認証
- `allowedSourceIPs` による送信元 IP 制限
- 任意コマンド実行なし
- キーボード入力注入に用途を限定

## Operational Guidance

- `sharedToken` には十分に長いランダム文字列を使ってください
- `allowedSourceIPs` は必要最小限にしてください
- ルーターで外部公開しないでください
- VPN やポート開放前提の用途には使わないでください
- 公開リポジトリへ `*.local.json` を含めないでください

## Reporting

公開Issueに秘密情報を書かず、再現条件だけを共有してください。
