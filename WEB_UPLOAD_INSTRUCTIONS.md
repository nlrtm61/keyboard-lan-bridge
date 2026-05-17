# GitHub Web Upload

このフォルダは、GitHub の Web 画面からそのままアップロードするための公開用一式です。

## 手順

1. GitHub で新しい空の公開リポジトリを作成する
2. `Add a README file`、`.gitignore`、`license` は選ばない
3. 作成後のリポジトリ画面で `uploading an existing file` を開く
4. このフォルダの中身をすべてドラッグ&ドロップする
5. Commit message に `Initial open source release` と入れて commit する

## アップロードするもの

- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `Package.swift`
- `Sources/`
- `configs/`
- `docs/`
- `scripts/`
- `launchd/`
- `app/`
- `.gitignore`

## アップロードしないもの

- `.git/`
- `.build/`
- `configs/*.local.json`
- ログ

## 公開前の最終目視ポイント

- `configs/` に実IPや実トークンが入っていないか
- `docs/` に自分のユーザー名や絶対パスが入っていないか
- README の説明が公開向けとして自然か
