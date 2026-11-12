import BarlessTestSupport
import CoreGraphics
import DeviceCatalog
import ImageIOKit
import StatusBarAnalyzer
import StatusBarEditor
import StatusBarRenderer
import Testing

/// 「整える」: 消したうえで、定番の表示（9:41・電波 4 本・Wi-Fi 最大・電池満タン）に描き直す
struct TidyTests {
    private struct FixedTime: TimeTextRecognizing {
        let time: String

        func recognizeTimes(in image: CGImage) async throws -> [String] { [time] }
    }

    /// 要素ごとの、インクの重なり（IoU）の下限。描き直しの検証（`RedrawVerificationTests`）と同じ値
    private static let minimumOverlap: [String: Double] = ["time": 0.74, "cellular": 0.84, "wifi": 0.80, "battery": 0.68]

    private func fixture(named name: String) throws -> Fixture {
        try #require(try Fixtures.all().first { $0.name == name }, "\(name) が無い")
    }

    /// 上端の切り出しの下に、背景の色を足して、スクリーンショット全体の大きさにする
    private func fullSize(_ strip: Bitmap, fixture: Fixture) -> Bitmap {
        let fill = strip[strip.width / 2, 4 * fixture.scale]
        var full = Bitmap(width: fixture.width, height: fixture.height, fill: fill, colorSpace: strip.colorSpace)
        for y in 0..<strip.height {
            for x in 0..<strip.width {
                full[x, y] = strip[x, y]
            }
        }
        return full
    }

    /// 残量 12%・電波 1 本・23:58 の画像を整えると、同じ機種の「9:41・満タン」の画像（= 正解）とほぼ重なる。
    /// iOS 18.6 の画像で比べる（iOS 26・27 の Simulator は、満タンを「充電中」の緑で写すため）
    @Test(arguments: [
        "iPhone-16__iOS-18-6__light-low",
        "iPhone-11__iOS-18-6__light-low",
        "iPhone-13-mini__iOS-18-6__light-low",
        "iPhone-SE-3rd-generation__iOS-18-6__light-low"
    ])
    func tidiedImageMatchesStandardScreenshot(name: String) async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: name)
        let reference = try self.fixture(named: name.replacingOccurrences(of: "light-low", with: "light-full")).loadStrip()
        let layout = try #require(fixture.expectedLayout(in: catalog))
        let strip = try fixture.loadStrip()
        let input = fullSize(strip, fixture: fixture)
        let editor = StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: fixture.time))

        let result = try await editor.edit(input.makeCGImage())

        #expect(result.statusBar?.layout.id == layout.id)
        let tidied = try Bitmap(cgImage: try #require(result.tidied))
        #expect(tidied.width == fixture.width && tidied.height == fixture.height)
        let background = Verification.flatBackground(of: reference, scale: fixture.scale)
        for element in Verification.elementRects(of: layout, timeText: "9:41") {
            let area = element.rect.insetBy(dx: -2 * layout.scale, dy: -2 * layout.scale)
            let overlap = ImageMetrics.inkOverlap(truth: reference, rendered: tidied, background: background, in: area)
            #expect(overlap >= Self.minimumOverlap[element.name] ?? 1, "\(fixture) \(element.name): 重なり \(overlap)")
        }
        // 帯の下は 1 画素も変わらない
        let band = Verification.band(of: layout)
        let below = PixelRect(x: 0, y: band.maxY, width: input.width, height: input.height - band.maxY)
        #expect(ImageMetrics.difference(tidied, input, in: below).maxAbsolute == 0)
        // 「隠す」の画像は、描き直しの影響を受けない
        let hidden = try Bitmap(cgImage: result.hidden)
        #expect(ImageMetrics.difference(hidden, Verification.flatBackground(of: input, scale: fixture.scale), in: band).maxAbsolute == 0)
    }

    /// ノッチ・Dynamic Island の機種には、残すものも、ずらすものも無い
    @Test
    func plansNothingSpecialForLeadingTimeLayouts() throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: "iPhone-17__iOS-27-0__light-low")
        let analysis = StatusBarAnalyzer.analyze(
            strip: try fixture.loadStrip(), pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog
        )
        #expect(analysis.tidyPlan() == .plain)
    }

    /// ホームボタンの機種（電波・キャリア名・Wi-Fi が左に並ぶ）: キャリア名は消さずに残す
    @Test(arguments: ["iPhone-SE-3rd-generation__iOS-18-6__light-low", "iPhone-SE-3rd-generation__iOS-27-0__dark-full"])
    func keepsCarrierName(name: String) async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: name)
        let layout = try #require(fixture.expectedLayout(in: catalog))
        let carrier = try #require(layout.carrier)
        let strip = try fixture.loadStrip()
        let analysis = StatusBarAnalyzer.analyze(strip: strip, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog)
        let plan = try #require(analysis.tidyPlan())
        // Simulator の画像は、配置を実測したときと同じキャリア名（Carrier）なので、Wi-Fi はずれない
        #expect(plan.wifiShiftX == 0 && plan.drawsWiFi)
        #expect(plan.kept.count == 1)
        #expect(plan.kept.first?.maxEdgeDistance(to: carrier) ?? .max <= layout.scale)

        let input = fullSize(strip, fixture: fixture)
        let editor = StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: fixture.time))
        let result = try await editor.edit(input.makeCGImage())

        let tidied = try Bitmap(cgImage: try #require(result.tidied))
        #expect(ImageMetrics.difference(tidied, input, in: carrier).maxAbsolute == 0)
        // 「隠す」では、キャリア名も消える
        let hidden = try Bitmap(cgImage: result.hidden)
        #expect(ImageMetrics.difference(hidden, input, in: carrier).maxAbsolute > 0)
    }

    /// キャリア名が長い画像: Wi-Fi は、キャリア名のすぐ右（元の画像で Wi-Fi があった位置）に描く
    @Test
    func followsLongerCarrierName() async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: "iPhone-SE-3rd-generation__iOS-18-6__light-full")
        let layout = try #require(fixture.expectedLayout(in: catalog))
        let carrier = try #require(layout.carrier)
        let original = try fixture.loadStrip()
        // キャリア名を 2 つ並べて長くし、Wi-Fi をその右へ動かした画像を作る
        let shift = carrier.width + 2 * layout.scale
        var strip = original
        let flat = original[original.width / 2, 4 * fixture.scale]
        for y in 0..<original.height {
            for x in layout.wifi.x..<(layout.wifi.maxX + shift) { strip[x, y] = flat }
            for x in carrier.x..<carrier.maxX { strip[x + shift, y] = original[x, y] }
            for x in layout.wifi.x..<layout.wifi.maxX { strip[x + shift, y] = original[x, y] }
        }
        let analysis = StatusBarAnalyzer.analyze(strip: strip, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog)
        #expect(analysis.decision.layout?.id == layout.id)
        let plan = try #require(analysis.tidyPlan())
        #expect(plan.wifiShiftX == shift && plan.drawsWiFi)

        let input = fullSize(strip, fixture: fixture)
        let editor = StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: fixture.time))
        let result = try await editor.edit(input.makeCGImage())

        // 描き直した Wi-Fi が、元の Wi-Fi とほぼ重なる。長いキャリア名はそのまま残る
        let tidied = try Bitmap(cgImage: try #require(result.tidied))
        let background = Verification.flatBackground(of: strip, scale: fixture.scale)
        let wifi = PixelRect(x: layout.wifi.x + shift, y: layout.wifi.y, width: layout.wifi.width, height: layout.wifi.height)
            .insetBy(dx: -2 * layout.scale, dy: -2 * layout.scale)
        let overlap = ImageMetrics.inkOverlap(truth: strip, rendered: tidied, background: background, in: wifi)
        #expect(overlap >= Self.minimumOverlap["wifi"] ?? 1, "重なり \(overlap)")
        let longCarrier = PixelRect(x: carrier.x, y: carrier.y, width: carrier.width + shift, height: carrier.height)
        #expect(ImageMetrics.difference(tidied, input, in: longCarrier).maxAbsolute == 0)
    }

    /// Wi-Fi が写っていない画像: キャリア名のすぐ右に描く（Simulator のキャリア名なら、配置の位置と同じ）
    @Test
    func placesWiFiAfterCarrierWhenAbsent() throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: "iPhone-SE-3rd-generation__iOS-18-6__light-full")
        let layout = try #require(fixture.expectedLayout(in: catalog))
        var strip = try fixture.loadStrip()
        let flat = strip[strip.width / 2, 4 * fixture.scale]
        for y in 0..<strip.height {
            for x in layout.wifi.x..<layout.wifi.maxX { strip[x, y] = flat }
        }
        let analysis = StatusBarAnalyzer.analyze(strip: strip, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog)
        let plan = try #require(analysis.tidyPlan())
        #expect(plan.kept.count == 1)
        #expect(abs(plan.wifiShiftX) <= layout.scale && plan.drawsWiFi)
    }
}
