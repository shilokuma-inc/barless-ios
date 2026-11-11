import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import Testing

/// 検証 2（描き直し）: 消した上に同じ中身を自作のベクターで描き、Simulator・実機の画像（= 正解）と重ねて比べる
/// （docs/verification.md）
struct RedrawVerificationTests {
    /// 要素ごとの、インクの重なり（IoU）の下限。実測の最小値より少し下に置いている
    private static let minimumOverlap: [String: Double] = ["time": 0.74, "cellular": 0.84, "wifi": 0.80, "battery": 0.68]
    /// インクの範囲の 4 辺のずれの上限（px）。3 倍の画像で 1pt
    private static let maximumEdgeDistance = 3

    @Test
    func matchesReferenceOnSolidBackground() throws {
        let catalog = try DeviceCatalog.bundled()
        var count = 0
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            let strip = try fixture.loadStrip()
            let background = Verification.flatBackground(of: strip, scale: fixture.scale)
            let (_, results) = try #require(
                Verification.redraw(fixture, input: strip, background: background, catalog: catalog), "\(fixture)"
            )
            for result in results {
                let minimum = Self.minimumOverlap[result.element] ?? 1
                #expect(result.overlap >= minimum, "\(fixture) \(result.element): 重なり \(result.overlap)")
                #expect(result.edgeDistance <= Self.maximumEdgeDistance, "\(fixture) \(result.element): 辺のずれ \(result.edgeDistance)px")
                count += 1
            }
        }
        // 125 枚 × 4 要素から、撮影の揺れで Wi-Fi が写っていない 2 枚分を除く
        #expect(count == 498)
    }
}
