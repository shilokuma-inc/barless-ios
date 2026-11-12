import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
@testable import StatusBarAnalyzer
import Testing

/// 帯を横切る背景の輪郭（建物の縁・壁紙の模様など）を、インクの中から見分ける（docs/verification.md §3）
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
        }
    }
}
