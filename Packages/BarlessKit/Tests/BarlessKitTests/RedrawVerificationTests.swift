import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import StatusBarRenderer
import Testing

/// 検証 2（描き直し）: 消した上に同じ中身を自作のベクターで描き、Simulator・実機の画像（= 正解）と重ねて比べる
/// （docs/verification.md）
struct RedrawVerificationTests {
    /// 要素ごとの、インクの重なり（IoU）の下限。実測の最小値より少し下に置いている
    private static let minimumOverlap: [String: Double] = ["time": 0.74, "cellular": 0.84, "wifi": 0.80, "battery": 0.68]
    /// インクの範囲の 4 辺のずれの上限（px）。3 倍の画像で 1pt
    private static let maximumEdgeDistance = 3
    /// インクの色の差（輪郭を除いた内側の画素の、チャンネルあたりの差の平均）の上限。実測の最大は時刻 8.4・電池 4.4
    private static let maximumColorDifference: [String: Double] = ["time": 12, "cellular": 12, "wifi": 12, "battery": 8]

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
                let colorLimit = Self.maximumColorDifference[result.element] ?? 0
                #expect(result.colorDifference <= colorLimit, "\(fixture) \(result.element): 色の差 \(result.colorDifference)")
                count += 1
            }
        }
        // 125 枚 × 4 要素から、撮影の揺れで Wi-Fi が写っていない 2 枚分を除く
        #expect(count == 498)
    }

    /// 色の検査が効いていること: 残量 12%（赤）の画像を「充電中」（緑）で描くと、形はほぼ同じでも電池の色の差が上限を超える
    @Test(arguments: ["iPhone-16__iOS-18-6__light-low", "iPhone-16__iOS-27-0__light-low"])
    func detectsWrongBatteryColor(name: String) throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try #require(try Fixtures.all().first { $0.name == name })
        let strip = try fixture.loadStrip()
        let background = Verification.flatBackground(of: strip, scale: fixture.scale)
        var wrong = fixture.spec
        wrong.battery = BatterySpec(level: 0.12, state: .charging)
        let output = try #require(
            Pipeline.run(strip, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog, redraw: wrong)
        )
        let area = output.layout.battery.insetBy(dx: -2 * output.layout.scale, dy: -2 * output.layout.scale)
        let difference = try #require(
            ImageMetrics.inkColorDifference(truth: strip, rendered: output.redrawn, background: background, in: area)
        )
        #expect(difference > (Self.maximumColorDifference["battery"] ?? 0), "色の差 \(difference)")
    }
}
