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
- 電池の形の見分け（iOS 18〜26 の枠あり / iOS 27 のカプセル形）は、「塗り → 途切れ → 塗り」と並ぶところまで見る。途切れ（背景との差が下がる）だけで決めると、iOS 27 の残量が少ない電池（残量の色 → 空いている部分の薄い色）を、背景の色によっては iOS 18〜26 と取り違える（2026-11-12）
- JPEG で再圧縮された画像では、電池の枠の内側のすき間が背景の色に戻りきらない。すき間があるかは、背景との差の絶対値ではなく、それまでの最大との比で見る（絶対値で見ると、iPhone 11・SE の iOS 18〜26 の画像を iOS 27 と誤る）（2026-11-12）
- アイコンの形は、カタログに入れた細部の実測（電波の棒 4 本・Wi-Fi の 3 つの帯・電池の本体と突起）にそのまま合わせて描く。比率を決め打ちにすると、iOS 27 の古い機種（棒の高さの比が新しい機種と違う）で合わなくなる（2026-11-12）

- 背景の輪郭（建物の縁・壁紙の模様の縁）が帯を斜めに横切ると、背景の見込み（上下の行の直線補間）がその列で外れ、輪郭の一部をインクとして拾う。文字とアイコンは帯の端（基準の行）から 3pt 離れているので、帯の端から 1pt 以内まで届いているインクのかたまりは背景の輪郭だと分かる。背景の種類（複雑）の判定は帯の全体を見るので、帯の一部だけを横切る輪郭は「グラデーション」のままになる。種類の判定のしきい値を動かして拾おうとしない（2026-11-12）
- まっすぐ縦に通る輪郭は、上下の基準の行で色が同じなので、インクとして拾えない（斜めの輪郭とは別の見つけ方が要る）。基準の行そのものの、横方向の色の変化で見つける。上の行と下の行の両方に変化があることを条件にすると、JPEG のにじみ（片方の行にしか出ない）や壁紙を巻き込まない（2026-11-12）
- iOS 26.5 と 27.0 のホーム画面の壁紙は、模様の縁が帯を横切る（時刻と Dynamic Island のあいだなど、文字もアイコンも無い所）。拾ったインクを全部消すと、そこが小さくぼやける。消すのは文字・アイコンの範囲（実測の矩形 + 2pt）の中だけにする（2026-11-12）
- 消した跡の量を数値で比べたいときは、写真に確認用のステータスバーを `StatusBarRenderer` で描いた画像を作る。背景だけの画像が手元に残るので、消した後との差を測れる（Simulator で撮った壁紙の画像は、背景だけの画像が無いので測れない）。写真は非公開の barless-spec の `design/assets/` にある。このリポジトリには入れず、テストには作った背景（`SyntheticEdge` など）を使う（2026-11-12）

- ホームボタンの機種（iPhone SE）は、左に「電波・キャリア名・Wi-Fi」が並び、Wi-Fi の位置がキャリア名の長さで変わる。カタログの Wi-Fi の位置は Simulator のキャリア名（Carrier）で測った値なので、描き直すときにそのまま使わない。キャリア名の右端から、実測と同じすき間（カタログの `wifi.x - carrier.maxX`）を空けて置く。元の Wi-Fi の位置を使う方法は、薄い Wi-Fi（0 本）の縁が拾えず 1px ほどずれるので採らなかった（2026-11-12）
- iOS 26・27 の Simulator は「満タン・充電済み」を緑 + 稲妻で写すので、「整える」（満タン・充電なし）の正解の画像に使えない。重なりを比べるテストは iOS 18.6 の画像で行う（2026-11-12）

## ビルド・テスト

- SwiftLint は `Packages/BarlessKit/.build`（`swift test` の生成物）も拾う。`.swiftlint.yml` の `excluded` に `Packages/*/.build` を入れてある（2026-11-12）
- 画素を 1 つずつ触る処理は、最適化なし（Debug）だと極端に遅い（パッケージのテスト全体が 36 秒 → 最適化をかけると 1.6 秒）。`Package.swift` で、画像を扱うターゲットとテストに Debug でも `-O` を付けている（`unsafeFlags`。ローカルパッケージなので使える）。新しいターゲットで画素を触るなら同じ設定を付ける（2026-11-12）
- 検証の数値と画像を全部作り直す処理は、ふだんのテストから分けてある（`VerificationReportTests`。環境変数 `BARLESS_REPORT_DIR` を渡したときだけ動く。`Tools/statusbar/make-verification-report.sh`）。Simulator で流すときは `TEST_RUNNER_BARLESS_REPORT_DIR=<出力先> xcodebuild test … -only-testing:BarlessKitTests/VerificationReportTests`（2026-11-12）
- パッケージのテスト（`BarlessKitTests`）をアプリのスキームに入れるには、pbxproj でパッケージを**フォルダの参照**（`PBXFileReference`、`lastKnownFileType = wrapper`）として持つ必要がある。`XCLocalSwiftPackageReference` で参照すると、スキームに `TestableReference` を書いても「isn’t a member of the specified test plan or scheme」になり、テストが黙って流れない（アプリのテスト 2 件だけで `TEST SUCCEEDED` になる）。pbxproj を触ったら、ログに `BarlessKitTests` のテスト数（38 件ほど）が出ているかを見る（2026-11-12）
- macOS 27 と Xcode 27.1 が入った Mac では、Xcode 26.6 の `xcodebuild test` が Simulator につながらず、6 分待って「The test runner hung before establishing connection」で落ちることがある（ビルドと `build-for-testing` は通る）。手元で Simulator のテストを流すときは `DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer` を付ける。CI は Xcode 26.6 のまま（2026-11-12）
- このリポジトリは公開している。仕様書と企画時の資料（価格・収益化・審査対策・商標の下調べなど）は非公開の `shilokuma-inc/barless-spec` に置き、ここには書き写さない。コードやドキュメントからは「仕様書 §5-2」のように節の番号だけで参照する（2026-11-12）
- 一度 PR に入ったファイルは、ブランチから消しても GitHub 上の PR の履歴（コミット一覧・force push の前後の比較）から読める。公開したくないファイルを入れてしまったら、公開する前にリポジトリを作り直すしかない（このリポジトリは 2026-11-12 に、仕様書を含まない履歴で作り直した）（2026-11-12）
- Upload（TestFlight への配信）は有効にしてある（リポジトリ変数 `ENABLE_DELIVERY=true`）。App Store Connect にアプリ（Bundle ID `jp.shilokuma.Barless`）を作るまでは、develop への push のたびに Upload が「App Store Connect にアプリがありません」で失敗する。Job Summary に出る手順でアプリを作ってから、失敗した実行をやり直す（2026-11-12）

## 画面・UI テスト

- アプリのターゲットは、既定のアクター分離が MainActor（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`）で、`SWIFT_APPROACHABLE_CONCURRENCY` も有効。何も書かない型と関数はメインスレッドで動き、`nonisolated` を付けただけの `async` 関数も呼び出し元（メイン）で動く。画像の展開・解析・書き出しのように重い処理は、型に `nonisolated`、関数に `@concurrent` を付けてメインの外へ出す（クロージャは `{ @concurrent in … }`）。パッケージ（BarlessKit）はこの設定の外なので、`async` 関数はそのままメインの外で動く（2026-11-12）
- `PhotosPicker` のインライン表示（`.photosPickerStyle(.inline)`）に `.screenshots` を指定すると、Simulator では「写真がありません」になる。`simctl addmedia` で入れた画像は、全画面の選択では「スクリーンショット」と読み上げられるのに、この絞り込みには入らない。Simulator で中身を確かめられないので、ホームの「最近のスクショ」は入れていない。入れるなら実機で確かめる。インライン表示は、初回に iOS の説明（「写真へのプライベートアクセス」）が枠いっぱいに出る点にも注意（2026-11-12）
- 写真の選択の画面（`PhotosPicker`）は UI テストから操作できる。写真は `app.images.matching(identifier: "PXGGridLayout-Info")` で取れるが、別のプロセスが描いているので `tap()` は「not hittable」で失敗する。`coordinate(withNormalizedOffset:).tap()` で画面の位置を押す（iOS 26.5 の Simulator）。並びは新しい順で、アプリから保存した画像が先頭に入るので、流すたびに番号がずれる（2026-11-12）
- 写真への追加の許可の確認は SpringBoard が出す。UI テストでは `XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts` で押せる。拒否した状態は `xcrun simctl privacy <udid> revoke photos-add <Bundle ID>`、元に戻すのは `reset` で作れる（2026-11-12）
- UI テストの中で撮った画面は、`XCUIScreen.main.screenshot().pngRepresentation` を Mac のパスにそのまま書き出せる（Simulator のテストランナーは Mac のファイルに書ける）。出力先は `TEST_RUNNER_` を付けた環境変数で渡す。PR 用の画像をこれで撮ると、iOS の画面（写真の選択・許可の確認）も写せる（2026-11-12）
- Simulator の言語は `xcrun simctl spawn <udid> defaults write "Apple Global Domain" AppleLanguages -array ja`（と `AppleLocale ja_JP`）のあと、shutdown → boot で変わる。アプリに `-AppleLanguages` を渡すだけでは、iOS が出す確認（権限の文言）は端末の言語のままになる（2026-11-12）
- 文字サイズを大きくした表示は `xcrun simctl ui <udid> content_size accessibility-large`、戻すのは `content_size large`（2026-11-12）
- 文言のカタログ（`Localizable.xcstrings`）は、コマンドラインのビルドでは書き換わらない（コードから文言を拾ってカタログに足すのは Xcode の画面でビルドしたときだけ）。文言を足したら、カタログにも手で足す。カタログに無い文言は、日本語でも英語のまま出る（2026-11-12）
