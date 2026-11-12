import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
@testable import StatusBarAnalyzer
import Testing

/// 帯を横切る背景の輪郭（建物の縁・壁紙の模様など）の扱い（docs/verification.md §3）。
///
/// 輪郭はインクとして拾われることがある。文字・アイコンの外にあるものは消さず、
/// 文字・アイコンの後ろを通っているときは「跡が残りそう」と伝える
struct StructureDetectionTests {
    /// 帯の上端か下端まで届くインクのかたまりだけを、背景の輪郭とみなす
    @Test
    func marksOnlyInkReachingBandEdge() {
        var mask = PixelMask(originX: 5, originY: 10, width: 14, height: 8)
        // 上端から斜めに続くかたまり
        for (x, y) in [(6, 10), (6, 11), (7, 12), (8, 13)] { mask[x, y] = true }
        // どの端にも届かないかたまり（文字やアイコンに当たる）
        for (x, y) in [(12, 13), (12, 14), (13, 14)] { mask[x, y] = true }
        // 下端に届くかたまり
        for (x, y) in [(16, 16), (16, 17)] { mask[x, y] = true }

        let structure = InkDetector.structure(in: mask, edge: 1)

        #expect(structure.count == 6)
        #expect(structure[8, 13] && structure[16, 16])
        #expect(!structure[12, 13] && !structure[13, 14])
    }

    /// 端から 2 行目のインクは、`edge` を 2 にしたときだけ拾う
    @Test
    func edgeWidthDecidesHowCloseInkMustBe() {
        var mask = PixelMask(originX: 0, originY: 0, width: 6, height: 8)
        mask[2, 1] = true
        mask[2, 2] = true

        #expect(InkDetector.structure(in: mask, edge: 1).isEmpty)
        #expect(InkDetector.structure(in: mask, edge: 2).count == 2)
    }

    /// 単色の背景（設定アプリ・実機）では、輪郭を 1 つも拾わない。文字とアイコンは帯の端まで届かない
    @Test
    func findsNoStructureOnFlatBackground() throws {
        let catalog = try DeviceCatalog.bundled()
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            let analysis = StatusBarAnalyzer.analyze(
                strip: try fixture.loadStrip(), pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog
            )
            #expect(analysis.scan?.structure.isEmpty == true, "\(fixture)")
            #expect(!analysis.mayLeaveTraces, "\(fixture)")
        }
    }

    /// 輪郭が電池の後ろを通る背景: 配置が決まった画像では「跡が残りそう」と伝える。
    /// 電池の形で iOS の世代を決める機種（iPhone 11 系・SE）は、電池が読めないので「決められない」になる（誤った配置にはしない）
    @Test
    func warnsWhenEdgeCrossesBehindBattery() throws {
        let catalog = try DeviceCatalog.bundled()
        let fixtures = try Verification.representatives(in: catalog, variants: ["light-full", "dark-full"])
        var warned = 0
        for fixture in fixtures {
            let image = try Self.edgeImage(fixture, placement: .behindBattery, catalog: catalog)
            let analysis = StatusBarAnalyzer.analyze(
                strip: image.input, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog
            )
            guard let resolved = analysis.decision.layout else { continue }
            #expect(resolved.id == image.layout.id, "\(fixture)")
            #expect(analysis.hasStructureBehindInk, "\(fixture)")
            #expect(analysis.mayLeaveTraces, "\(fixture)")
            // 背景の種類だけでは見分けられない（だから別に見ている）
            #expect(analysis.background != .complex, "\(fixture)")
            warned += 1
        }
        #expect(fixtures.count == 48)
        #expect(warned == 32)
    }

    /// 輪郭が、文字もアイコンも無い所を通る背景: 輪郭には触らない。消した結果は、インクが無い背景と完全に同じになる
    @Test
    func leavesEdgeAwayFromInkUntouched() throws {
        let catalog = try DeviceCatalog.bundled()
        for fixture in try Verification.representatives(in: catalog, variants: ["light-full", "dark-full"]) {
            let image = try Self.edgeImage(fixture, placement: .awayFromInk, catalog: catalog)
            let output = try #require(
                Pipeline.run(image.input, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog), "\(fixture)"
            )
            #expect(output.layout.id == image.layout.id, "\(fixture)")
            #expect(!output.analysis.mayLeaveTraces, "\(fixture)")
            // 輪郭はインクとして拾われているが、消去の対象からは外れている
            #expect(output.analysis.scan?.structure.isEmpty == false, "\(fixture)")
            #expect(!output.analysis.backgroundInk().isEmpty, "\(fixture)")
            let difference = ImageMetrics.difference(output.erased, image.background, in: Verification.band(of: image.layout))
            #expect(difference.maxAbsolute == 0, "\(fixture): 差の最大 \(difference.maxAbsolute)")
        }
    }

    /// ホーム画面（壁紙）: iOS 26・27 の壁紙は模様の縁が帯を横切るが、文字・アイコンの後ろは通らないので、注意は出さない
    @Test
    func doesNotWarnOnHomeScreenWallpapers() throws {
        let catalog = try DeviceCatalog.bundled()
        var withStructure = 0
        for fixture in try Fixtures.supported().filter({ !$0.isSolidBackground }) {
            let analysis = StatusBarAnalyzer.analyze(
                strip: try fixture.loadStrip(), pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog
            )
            guard analysis.decision.layout != nil else { continue }
            #expect(!analysis.mayLeaveTraces, "\(fixture)")
            if !analysis.backgroundInk().isEmpty { withStructure += 1 }
            // iOS 18 の壁紙はなめらかで、輪郭が無い
            if fixture.runtime == "iOS-18-6" {
                #expect(analysis.backgroundInk().isEmpty, "\(fixture)")
            }
        }
        #expect(withStructure == 28)
    }

    /// Simulator のインクを、輪郭のある背景に移した画像
    private struct EdgeImage {
        let input: Bitmap
        /// インクが無い背景
        let background: Bitmap
        /// 正解の配置
        let layout: StatusBarLayout
    }

    private static func edgeImage(_ fixture: Fixture, placement: EdgePlacement, catalog: DeviceCatalog) throws -> EdgeImage {
        let layout = try #require(fixture.expectedLayout(in: catalog), "\(fixture)")
        let strip = try fixture.loadStrip()
        let background = placement.edge(for: layout, timeText: fixture.time)
            .make(width: strip.width, height: strip.height, isLight: fixture.appearance == "light")
        let input = Synthetic.transplantInk(from: strip, onto: background, scale: fixture.scale)
        return EdgeImage(input: input, background: background, layout: layout)
    }
}
