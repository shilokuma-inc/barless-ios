# Tools/statusbar — ステータスバーの実測

機種・iOS ごとのステータスバーの位置を Simulator で撮って測り、`DeviceCatalog` とテストのフィクスチャを作るためのスクリプト。
結果の読み方は [docs/device-table.md](../../docs/device-table.md)。

必要なもの: Xcode（測りたい iOS の Simulator ランタイム）、Python 3 と Pillow（`pip3 install pillow`）。

## 流れ

```
capture.sh / run-26-27.sh   Simulator で撮る          → Tools/statusbar/simshots/*.png（git には入れない）
analyze.py                  上端のインクを測る        → docs/device-table.json
make-table.py               表にする                  → docs/device-table.md
```

| スクリプト | 役割 |
| --- | --- |
| `capture.sh <機種> <ランタイム>` | 一時的な Simulator を作り、`simctl status_bar override` で表示を固定して設定アプリとホーム画面を 4 枚撮る（`light-full` / `light-low` / `dark-full` / `dark-home`）。出力先は環境変数 `CAP_OUT` |
| `run-26-27.sh [ランタイム…]` | 対象の全機種で `capture.sh` を 3 並列で流す。既定は iOS 26.5 と 27.0。撮り終えた組み合わせは飛ばす |
| `analyze.py <画像のディレクトリ>` | `*__light-full.png` と `*__light-low.png` の上端から、背景と違う色の画素（時刻・アイコン）のかたまりを測って JSON を出す |
| `make-table.py <JSON>` | JSON から `docs/device-table.md` の表（§1・§2）を作る |
| `build-table.sh [画像のディレクトリ]` | `analyze.py` → `make-table.py` を続けて流し、`docs/device-table.json` と `docs/device-table.md` を作り直す。表の前の文章は `device-table.head.md` |

## 撮り直す・機種を足す

```bash
Tools/statusbar/run-26-27.sh iOS-18-6 iOS-26-5 iOS-27-0   # 撮る（1 組み合わせ 1〜2 分）
Tools/statusbar/build-table.sh                             # 測って表を作り直す
```

- 画像のファイル名は `<機種>__<ランタイム>__<状態>.png`（例: `iPhone-17__iOS-27-0__light-full.png`）
- `light-full` / `dark-full` / `dark-home` は 9:41・電波 4 本・Wi-Fi 3 本・電池 100%（充電済み）、`light-low` は 23:58・電波 1 本・Wi-Fi なし・電池 12%
- 撮った画像（168 枚で約 130MB）は `.gitignore` で除外している。リポジトリには上端だけを切り出したフィクスチャを置く
