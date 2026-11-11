import BarlessTestSupport
import DeviceCatalog
import Foundation
import Testing

/// 検証結果（docs/verification/results.md と images/）を作り直す。
///
/// ふだんのテストでは動かない。環境変数 `BARLESS_REPORT_DIR` に出力先を渡したときだけ動く
/// （`Tools/statusbar/make-verification-report.sh` から呼ぶ）。
struct VerificationReportTests {
    private static var directory: URL? {
        ProcessInfo.processInfo.environment["BARLESS_REPORT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    @Test(.enabled(if: directory != nil))
    func writesReport() async throws {
        let directory = try #require(Self.directory)
        let images = directory.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let catalog = try DeviceCatalog.bundled()
        let fixtures = try Fixtures.supported()
        let sections = ReportSections(catalog: catalog, fixtures: fixtures)
        let measurements = ReportMeasurements(catalog: catalog, fixtures: fixtures)
        let parts: [String] = [
            "# 検証結果の数値（自動生成）\n",
            "`Tools/statusbar/make-verification-report.sh` が作るファイル。手で直さない。読み方と結論は [../verification.md](../verification.md)。\n",
            "- カタログの更新日: \(catalog.updatedAt)（配置 \(catalog.layouts.count) 件）",
            "- 画像: \(fixtures.count) 枚（Simulator 164 枚 + 実機 2 枚。iPhone Duo の 4 枚は対象外）\n",
            "## 1. 判定（機種グループ × iOS の世代）\n", try sections.decision(),
            "## 2. 文字認識（Vision）で時刻を読む\n", try await sections.recognition(),
            "## 3. 時刻の組み方（フォントの大きさと、中央ぞろえの見込み）\n", sections.typography(),
            "## 4. 消去\n", "### 4-1. 単色の背景\n", try measurements.eraseOnSolid(),
            "### 4-2. グラデーションの背景（作った背景に Simulator のインクを移した画像）\n", try measurements.eraseOnGradient(),
            "### 4-3. ホーム画面（壁紙）\n", try measurements.wallpaper(),
            "### 4-4. 再圧縮した画像（単色の背景の画像を JPEG で保存し直したもの。大きさはそのまま）\n", try measurements.eraseOnRecompressed(),
            "## 5. 描き直し（単色の背景で、消してから同じ中身を描き、元の画像と比べる）\n", try measurements.redraw()
        ]
        try parts.joined(separator: "\n").write(to: directory.appendingPathComponent("results.md"), atomically: true, encoding: .utf8)
        try writeImages(ReportImages(catalog: catalog, fixtures: fixtures, directory: images))
    }

    private func writeImages(_ images: ReportImages) throws {
        let solid = [
            "iPhone-16__iOS-18-6__light-full", "iPhone-16__iOS-18-6__light-low", "iPhone-16__iOS-26-5__dark-full",
            "iPhone-16__iOS-27-0__light-full", "iPhone-16__iOS-27-0__light-low", "iPhone-17__iOS-27-0__dark-full",
            "iPhone-11__iOS-18-6__light-low", "iPhone-SE-3rd-generation__iOS-27-0__light-full",
            "16ProMax_iOS27.2_std-light_top", "16ProMax_iOS27.2_std-dark_top"
        ]
        for name in solid { try images.redraw(name) }
        try images.tidy(input: "iPhone-16__iOS-18-6__light-low", reference: "iPhone-16__iOS-18-6__light-full")
        for kind in SyntheticBackground.allCases {
            try images.gradient("iPhone-17__iOS-27-0__light-full", kind: kind)
        }
        try images.gradient("iPhone-16__iOS-18-6__dark-full", kind: .diagonal)
        let wallpapers = [
            "iPhone-17__iOS-27-0__dark-home", "iPhone-16__iOS-18-6__dark-home", "iPhone-11__iOS-26-5__dark-home",
            "iPhone-SE-3rd-generation__iOS-18-6__dark-home", "iPhone-SE-3rd-generation__iOS-27-0__dark-home"
        ]
        for name in wallpapers { try images.wallpaper(name) }
    }
}
