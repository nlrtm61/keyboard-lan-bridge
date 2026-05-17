# Permissions

## Receiver

- 必須: Accessibility
- 必須: Post Event Access
- LaunchAgent 常駐前に、生成された受信側 `.app` へ権限を付与してください

確認:

```bash
.build/release/receiver permissions --prompt
```

## Sender

- 必須: Accessibility
- 必須: Listen Event Access
- 運用形態によっては Input Monitoring 相当の確認が必要です
- LaunchAgent 常駐前に、生成された送信側 `.app` へ権限を付与してください

確認:

```bash
.build/release/sender permissions --prompt
```

## 補足

- 未署名 app bundle を再配置したあと、macOS が別物と判定して権限が外れたように見えることがあります
- その場合は権限一覧で対象 `.app` を入れ直してください
