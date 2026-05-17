# Phase 3 Design Notes

## 現状

- API は `key` だけでなく `keyCode` を受け付ける
- `action` は `tap`, `down`, `up` を持つ
- `modifiers` は明示フィールドで持つ
- `Shift+Escape` で `LOCAL` / `REMOTE` を切り替える
- `REMOTE` 中は `keyDown`, `keyUp`, `flagsChanged` を `keyCode` ベースで送る

## 次段階

1. `sequence` を単調増加にして順序検証を入れる
2. Receiver で押下状態を持ち、modifier の down/up を正確に再現する
3. キー配列差を吸収するために
   - 送信時は `keyCode`
   - 必要に応じて `characters`
   - キーボードレイアウト識別子
   を追加する
4. リピートと取りこぼし対策として
   - sender 側 ACK/再送
   - receiver 側 stuck key timeout
   - emergency release-all
   を入れる
5. メニューバー常駐 UI と送信状態表示を追加する
6. `CapsLock` を受信側入力ソース切替として扱う
7. sender / receiver のログをローテーションする

## IME

- 日本語IMEの完全同期はこの段階では未解決
- まずは物理キー相当の転送を優先し、文字列同期ではなくキーボードイベント同期を維持する
- `CapsLock` は受信側で Latin レイアウトと Japanese IME を切り替える近似解として扱う
- 変換中テキスト、候補ウインドウ、確定前状態は同期しない

## JIS / US

- 現在の通常キー転送は `keyCode` ベース
- 英数字、矢印、修飾キーは比較的安定
- 記号キーは送信側/受信側レイアウト差に影響される
- `/health` の `currentKeyboardLayoutID` と `currentInputSourceID` で差異を切り分ける
