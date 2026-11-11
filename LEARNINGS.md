# LEARNINGS — このリポジトリ固有の知見

開発の中で分かった、**barless-ios だけで通じる知見**を溜める。全リポジトリ共通の知見は `~/.agents/LEARNINGS.md` に書く。

- 1 項目 = 1 つの箇条書き。見出しの下に追記する。日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かること、一度きりの作業の経過は書かない
- 古くなった項目は消すか直す

## 実測・カタログ

- iOS 27 は、位置がほぼ変わらない古い機種（iPhone 11 系・SE）でもアイコンの形が変わる（電池が枠なしのカプセル形になり、電波と Wi-Fi の端が丸くなる）。配置を iOS の世代をまたいでまとめてはいけない。これらの機種は時刻の位置と大きさが世代で同じなので、世代は電池の形（枠のすぐ内側に背景の色のすき間があるか）で見分ける（2026-11-12）
- 要素を分けるすき間のしきい値は 3pt。要素の中のすき間は 2pt 以下、要素どうしは 4.5pt 以上ある（iPhone 11・13 mini・SE がいちばん狭い）。5pt にすると、これらの機種で右側のアイコンが 1 かたまりになる（2026-11-12）
- `simctl status_bar override` で撮った画像には揺れがある。iPhone 12・iOS 26.5 の `light-low` と `dark-full` は Wi-Fi が写っていない。また「充電済み・100%」は、iOS 18.6 では黒い満タン、iOS 26.5 と 27.0 では緑 + 稲妻で表示される（2026-11-12）
- 充電中のマーク（稲妻）は電池の本体の上下に 1px はみ出す。電池の高さを測るときは、稲妻のない列（本体の左から 1/4）で測る（2026-11-12）
- Simulator のスクリーンショットは sRGB、実機は Display P3。`make-fixtures.py`（Pillow）で切り出すと色のプロファイルが落ちるので、実機の画像は切り出し済みのファイルをそのまま `Fixtures/realshots/` に置く（2026-11-12）

## 判定・描画

- 時刻は中央ぞろえだが、文字列が変わると中心が 1px ほど揺れる。フォントの大きさは複数の実測（9:41 と 23:58）から決め、位置は 9:41 の実測に合わせている（2026-11-12）
- Vision の文字認識（`RecognizeTextRequest`）は、帯全体（幅 1200px ほど・文字の高さ 36px ほど）をそのまま渡すと、暗い画像でまれに時刻を見落とす（166 枚中 2 枚）。時刻のまわりだけを切り出して 3 倍に拡大して渡すと 166 枚すべて読め、かかる時間も 3 分の 1 ほどになる（2026-11-12）
- JPEG で再圧縮された画像では、電池の枠の内側のすき間が背景の色に戻りきらない。すき間があるかは、背景との差の絶対値ではなく、それまでの最大との比で見る（絶対値で見ると、iPhone 11・SE の iOS 18〜26 の画像を iOS 27 と誤る）（2026-11-12）
- アイコンの形は、カタログに入れた細部の実測（電波の棒 4 本・Wi-Fi の 3 つの帯・電池の本体と突起）にそのまま合わせて描く。比率を決め打ちにすると、iOS 27 の古い機種（棒の高さの比が新しい機種と違う）で合わなくなる（2026-11-12）

## ビルド・テスト

- SwiftLint は `Packages/BarlessKit/.build`（`swift test` の生成物）も拾う。`.swiftlint.yml` の `excluded` に `Packages/*/.build` を入れてある（2026-11-12）
- 画素を 1 つずつ触る処理は、最適化なし（Debug）だと極端に遅い（パッケージのテスト全体が 36 秒 → 最適化をかけると 1.6 秒）。`Package.swift` で、画像を扱うターゲットとテストに Debug でも `-O` を付けている（`unsafeFlags`。ローカルパッケージなので使える）。新しいターゲットで画素を触るなら同じ設定を付ける（2026-11-12）
- 検証の数値と画像を全部作り直す処理は、ふだんのテストから分けてある（`VerificationReportTests`。環境変数 `BARLESS_REPORT_DIR` を渡したときだけ動く。`Tools/statusbar/make-verification-report.sh`）。Simulator で流すときは `TEST_RUNNER_BARLESS_REPORT_DIR=<出力先> xcodebuild test … -only-testing:BarlessKitTests/VerificationReportTests`（2026-11-12）
- パッケージのテスト（`BarlessKitTests`）をアプリのスキームに入れるには、pbxproj でパッケージを**フォルダの参照**（`PBXFileReference`、`lastKnownFileType = wrapper`）として持つ必要がある。`XCLocalSwiftPackageReference` で参照すると、スキームに `TestableReference` を書いても「isn’t a member of the specified test plan or scheme」になり、テストが黙って流れない（アプリのテスト 2 件だけで `TEST SUCCEEDED` になる）。pbxproj を触ったら、ログに `BarlessKitTests` のテスト数（38 件ほど）が出ているかを見る（2026-11-12）
- macOS 27 と Xcode 27.1 が入った Mac では、Xcode 26.6 の `xcodebuild test` が Simulator につながらず、6 分待って「The test runner hung before establishing connection」で落ちることがある（ビルドと `build-for-testing` は通る）。手元で Simulator のテストを流すときは `DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer` を付ける。CI は Xcode 26.6 のまま（2026-11-12）
- このリポジトリは公開している。仕様書と企画時の資料（価格・収益化・審査対策・商標の下調べなど）は非公開の `shilokuma-inc/barless-spec` に置き、ここには書き写さない。コードやドキュメントからは「仕様書 §5-2」のように節の番号だけで参照する（2026-11-12）
- 一度 PR に入ったファイルは、ブランチから消しても GitHub 上の PR の履歴（コミット一覧・force push の前後の比較）から読める。公開したくないファイルを入れてしまったら、公開する前にリポジトリを作り直すしかない（このリポジトリは 2026-11-12 に、仕様書を含まない履歴で作り直した）（2026-11-12）
- Upload（TestFlight への配信）は、リポジトリ変数 `ENABLE_DELIVERY=false` で止めてある。App Store Connect にアプリを作って配信を始めるときに、この変数を消す（2026-11-12）
