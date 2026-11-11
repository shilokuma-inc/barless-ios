# Tools/statusbar — ステータスバーの実測と検証

機種・iOS ごとのステータスバーの位置を Simulator で撮って測り、`DeviceCatalog`（配置の JSON）とテストのフィクスチャを作るためのスクリプト。
実測の読み方は [docs/device-table.md](../../docs/device-table.md)、判定・消去・描き直しの検証結果は [docs/verification.md](../../docs/verification.md)。

必要なもの: Xcode（測りたい iOS の Simulator ランタイム）、Python 3 と Pillow（`pip3 install pillow`）。

## 流れ

```
capture.sh / run-26-27.sh       Simulator で撮る                → Tools/statusbar/simshots/*.png（git には入れない）
analyze.py                      上端のインクを測る              → docs/device-table.json
make-table.py                   表にする                        → docs/device-table.md
make-fixtures.py                上端 72pt を切り出す            → Packages/BarlessKit/Tests/BarlessTestSupport/Fixtures/
make-catalog.py                 配置にまとめ、アイコンの細部を測る → Packages/BarlessKit/Sources/DeviceCatalog/Resources/device-catalog.json
make-verification-report.sh     検証の数値と画像を作る          → docs/verification/results.md・images/
```

| スクリプト | 役割 |
| --- | --- |
| `capture.sh <機種> <ランタイム>` | 一時的な Simulator を作り、`simctl status_bar override` で表示を固定して設定アプリとホーム画面を 4 枚撮る（`light-full` / `light-low` / `dark-full` / `dark-home`）。出力先は環境変数 `CAP_OUT` |
| `run-26-27.sh [ランタイム…]` | 対象の全機種で `capture.sh` を 3 並列で流す。既定は iOS 26.5 と 27.0。撮り終えた組み合わせは飛ばす |
| `analyze.py <画像のディレクトリ>` | `*__light-full.png` と `*__light-low.png` の上端から、背景と違う色の画素（時刻・アイコン）のかたまりを測って JSON を出す |
| `make-table.py <JSON>` | JSON から `docs/device-table.md` の表（§1・§2）を作る |
| `build-table.sh [画像のディレクトリ]` | `analyze.py` → `make-table.py` を続けて流し、`docs/device-table.json` と `docs/device-table.md` を作り直す。表の前の文章は `device-table.head.md` |
| `make-fixtures.py <画像のディレクトリ> <Fixtures>` | 撮った画像の上端 72pt を切り出して `Fixtures/simshots/` に置き、一覧（`manifest.json`）を作る。実機の画像（`Fixtures/realshots/`。上端の切り出しを手で置く）も一覧に足す |
| `make-catalog.py <JSON> <Fixtures> <更新日>` | 実測を「機種グループ × iOS の世代」の配置にまとめ、電波の棒・Wi-Fi の帯・電池の本体と突起をフィクスチャの画像から測って、`DeviceCatalog` の JSON を標準出力に出す |
| `make-verification-report.sh [出力先]` | `VerificationReportTests`（`BARLESS_REPORT_DIR` を渡したときだけ動くテスト）を macOS で流し、検証の表と画像を作り直す |

## 撮り直す・機種や iOS を足す

```bash
Tools/statusbar/run-26-27.sh iOS-18-6 iOS-26-5 iOS-27-0   # 撮る（1 組み合わせ 1〜2 分）
Tools/statusbar/build-table.sh                             # 測って表を作り直す
python3 Tools/statusbar/make-fixtures.py Tools/statusbar/simshots Packages/BarlessKit/Tests/BarlessTestSupport/Fixtures
python3 Tools/statusbar/make-catalog.py docs/device-table.json Packages/BarlessKit/Tests/BarlessTestSupport/Fixtures "$(date +%F)" \
  > Packages/BarlessKit/Sources/DeviceCatalog/Resources/device-catalog.json
(cd Packages/BarlessKit && swift test)                     # 判定・消去・描き直しのテスト
Tools/statusbar/make-verification-report.sh                # 検証の表と画像を作り直す
```

- 画像のファイル名は `<機種>__<ランタイム>__<状態>.png`（例: `iPhone-17__iOS-27-0__light-full.png`）
- `light-full` / `dark-full` / `dark-home` は 9:41・電波 4 本・Wi-Fi 3 本・電池 100%（充電済み）、`light-low` は 23:58・電波 1 本・Wi-Fi なし・電池 12%
- 撮った画像（168 枚で約 130MB）は `.gitignore` で除外している。リポジトリには上端だけを切り出したフィクスチャ（約 6MB）を置く
- 新しい機種を足すときは `run-26-27.sh` の `types` に機種名を足す。iOS の世代が増えたら `make-catalog.py` の `GENERATION` と、`DeviceCatalog` の `OSGeneration` を足す
- 実機で撮った画像は、名前や通知が写らないよう上端 80pt だけを切り出して `Fixtures/realshots/` に置き、`make-fixtures.py` の `REALSHOTS` に大きさと写っている値を書く
