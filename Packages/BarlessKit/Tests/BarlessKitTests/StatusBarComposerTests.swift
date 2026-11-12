import BarlessTestSupport
import CoreGraphics
import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarAnalyzer
import StatusBarEditor
import StatusBarRenderer
import Testing

/// 「遊ぶ」: 解析した 1 枚のステータスバーを、中身を変えて描き直す
struct StatusBarComposerTests {
    /// 文字認識の代わりに、決まった時刻を返す（`nil` なら、読めなかったことにする）
    private struct FixedTime: TimeTextRecognizing {
        let time: String?

        func recognizeTimes(in image: CGImage) async throws -> [String] {
            time.map { [$0] } ?? []
        }
    }

    /// 編集した 1 枚と、比べるのに使うもの
    private struct Sample {
        let fixture: Fixture
        let layout: StatusBarLayout
        /// 元の画像（全体）
        let input: Bitmap
        /// 「隠す」の結果
        let hidden: Bitmap
        /// 「整える」の結果
        let tidied: Bitmap
        let composer: StatusBarComposer

        /// 時刻・電波・Wi-Fi・電池の範囲（2pt 広げたもの）
        func area(_ name: String, timeText: String) throws -> PixelRect {
            let element = try #require(Verification.elementRects(of: layout, timeText: timeText).first { $0.name == name })
            return element.rect.insetBy(dx: -2 * layout.scale, dy: -2 * layout.scale)
        }

        /// 帯の下
        var below: PixelRect {
            let band = Verification.band(of: layout)
            return PixelRect(x: 0, y: band.maxY, width: input.width, height: input.height - band.maxY)
        }
    }

    /// - Parameters:
    ///   - readsTime: 文字認識で時刻を読めたことにするか
    ///   - onlyExpectedLayout: カタログを、この画像の配置 1 つだけにするか（大きさだけで配置が決まるようになる）
    ///   - prepare: 解析の前に、上端の切り出しに手を加える（キャリア名を長くする・時刻を消す など）
    private func sample(
        _ name: String,
        readsTime: Bool = true,
        onlyExpectedLayout: Bool = false,
        prepare: (inout Bitmap, StatusBarLayout, RGB) -> Void = { _, _, _ in }
    ) async throws -> Sample {
        let bundled = try DeviceCatalog.bundled()
        let fixture = try #require(try Fixtures.all().first { $0.name == name }, "\(name) が無い")
        let layout = try #require(fixture.expectedLayout(in: bundled))
        let catalog = onlyExpectedLayout ? try Self.catalog(bundled, only: layout.id) : bundled
        // 上端の切り出しの下に、背景の色を足して、スクリーンショット全体の大きさにする
        var strip = try fixture.loadStrip()
        let fill = strip[strip.width / 2, 4 * fixture.scale]
        prepare(&strip, layout, fill)
        var input = Bitmap(width: fixture.width, height: fixture.height, fill: fill, colorSpace: strip.colorSpace)
        input.replaceTopRows(with: strip)
        let editor = StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: readsTime ? fixture.time : nil))
        let result = try await editor.edit(input.makeCGImage())
        return Sample(
            fixture: fixture,
            layout: layout,
            input: input,
            hidden: try Bitmap(cgImage: result.hidden),
            tidied: try Bitmap(cgImage: try #require(result.tidied)),
            composer: try #require(result.composer, "\(result.outcome)")
        )
    }

    /// 「整える」と同じ中身で描くと、「整える」の画像と 1 画素も違わない
    /// （上端だけを切り出して消しても、全体を消したときと同じ結果になる。ホームボタンの機種では、キャリア名も同じように残る）
    @Test(arguments: [
        "iPhone-16__iOS-18-6__light-low",
        "iPhone-17__iOS-27-0__dark-full",
        "iPhone-16__iOS-26-5__dark-home",
        "iPhone-SE-3rd-generation__iOS-18-6__light-low"
    ])
    func rendersSameImageAsTidy(name: String) async throws {
        let sample = try await sample(name)

        let rendered = try sample.composer.renderBitmap(.standard)

        #expect(rendered.width == sample.input.width && rendered.height == sample.input.height)
        #expect(rendered.data == sample.tidied.data)
        #expect(sample.composer.canKeepTime && sample.composer.canDrawWiFi)
    }

    /// 時刻の位置が分からない画像（文字を読めず、時刻のかたまりも無い）では、時刻を「そのまま」残せない。
    /// 「そのまま」を渡しても、隠したときと同じ画像になる
    @Test
    func cannotKeepTimeWhenTimeIsNotFound() async throws {
        // いまのカタログは、どの大きさにも配置が 2 つ以上あり、時刻が無いと配置が決まらない。
        // 配置が 1 つだけの大きさ（大きさだけで決まる）を、カタログを絞って作る
        let name = "iPhone-SE-3rd-generation__iOS-18-6__light-low"
        let sample = try await sample(name, readsTime: false, onlyExpectedLayout: true) { strip, layout, fill in
            let time = TimeTypography(layout: layout).inkRect(for: "23:58").insetBy(dx: -4 * layout.scale, dy: -2 * layout.scale)
            for y in time.y..<time.maxY {
                for x in time.x..<time.maxX { strip[x, y] = fill }
            }
        }
        var keep = PlaySpec.standard
        keep.time = .keep
        var hide = PlaySpec.standard
        hide.time = .hide

        #expect(!sample.composer.canKeepTime)
        #expect(try sample.composer.renderBitmap(keep).data == sample.composer.renderBitmap(hide).data)
    }

    /// キャリア名が長くて、時刻との間に Wi-Fi が入らない画像では、Wi-Fi を描けない。本数を渡しても描かない
    @Test
    func cannotDrawWiFiNextToLongCarrierName() async throws {
        let sample = try await sample("iPhone-SE-3rd-generation__iOS-18-6__light-full") { strip, layout, fill in
            guard let carrier = layout.carrier else { return }
            // Wi-Fi を消して、キャリア名を 3 つ、時刻のすぐ手前まで並べる
            let original = strip
            let shift = carrier.width + 9 * layout.scale
            for y in 0..<strip.height {
                for x in layout.wifi.x..<layout.wifi.maxX { strip[x, y] = fill }
                for copy in 1...2 {
                    for x in carrier.x..<carrier.maxX { strip[x + copy * shift, y] = original[x, y] }
                }
            }
        }
        var off = PlaySpec.standard
        off.wifiBars = nil

        #expect(!sample.composer.canDrawWiFi)
        #expect(sample.composer.canKeepTime)
        #expect(try sample.composer.renderBitmap(.standard).data == sample.composer.renderBitmap(off).data)
    }

    /// 時刻を「そのまま」にすると、時刻は元の画像のまま残り、ほかは描き直す
    @Test(arguments: ["iPhone-17__iOS-27-0__light-low", "iPhone-SE-3rd-generation__iOS-18-6__light-low"])
    func keepsOriginalTime(name: String) async throws {
        let sample = try await sample(name)
        var spec = PlaySpec.standard
        spec.time = .keep

        let rendered = try sample.composer.renderBitmap(spec)

        let time = try sample.area("time", timeText: sample.fixture.time)
        #expect(ImageMetrics.difference(rendered, sample.input, in: time).maxAbsolute == 0)
        // 電池は、残量 12% から満タンに描き直している
        let battery = try sample.area("battery", timeText: sample.fixture.time)
        #expect(ImageMetrics.difference(rendered, sample.input, in: battery).maxAbsolute > 100)
        #expect(ImageMetrics.difference(rendered, sample.tidied, in: battery).maxAbsolute == 0)
        #expect(ImageMetrics.difference(rendered, sample.input, in: sample.below).maxAbsolute == 0)
    }

    /// 時刻を「隠す」と、時刻のあった場所は消したまま。Wi-Fi をオフにすると、Wi-Fi のあった場所も消したまま
    @Test
    func hidesTimeAndWiFi() async throws {
        let sample = try await sample("iPhone-17__iOS-27-0__light-low")
        var spec = PlaySpec.standard
        spec.time = .hide
        spec.wifiBars = nil

        let rendered = try sample.composer.renderBitmap(spec)

        for (name, text) in [("time", sample.fixture.time), ("time", "9:41"), ("wifi", "9:41")] {
            let area = try sample.area(name, timeText: text)
            #expect(ImageMetrics.difference(rendered, sample.hidden, in: area).maxAbsolute == 0, "\(name) \(text)")
        }
        // 電波と電池は「整える」と同じ
        for name in ["cellular", "battery"] {
            let area = try sample.area(name, timeText: "9:41")
            #expect(ImageMetrics.difference(rendered, sample.tidied, in: area).maxAbsolute == 0, "\(name)")
        }
    }

    /// 値を変えると、その要素の範囲だけが変わる。帯の下は 1 画素も変わらない
    @Test(arguments: ["iPhone-17__iOS-27-0__dark-full", "iPhone-16__iOS-18-6__light-low"])
    func changesOnlyTheChosenElement(name: String) async throws {
        let sample = try await sample(name)
        let standard = try sample.composer.renderBitmap(.standard)
        let whole = PixelRect(x: 0, y: 0, width: sample.input.width, height: sample.input.height)

        var battery = PlaySpec.standard
        battery.battery = BatterySpec(level: 0.5)
        var cellular = PlaySpec.standard
        cellular.cellularBars = 1
        var wifi = PlaySpec.standard
        wifi.wifiBars = 1
        var time = PlaySpec.standard
        time.time = .set("12:25")

        for (element, spec, timeText) in [("battery", battery, "9:41"), ("cellular", cellular, "9:41"), ("wifi", wifi, "9:41")] {
            let rendered = try sample.composer.renderBitmap(spec)
            let area = try sample.area(element, timeText: timeText)
            #expect(ImageMetrics.difference(rendered, standard, in: area).maxAbsolute > 40, "\(element)")
            #expect(Self.differs(rendered, standard, outside: area, in: whole) == 0, "\(element)")
        }
        // 時刻は、文字列で幅が変わるので、前後の文字列の範囲を合わせて見る
        let rendered = try sample.composer.renderBitmap(time)
        let area = try sample.area("time", timeText: "9:41").union(try sample.area("time", timeText: "12:25"))
        #expect(ImageMetrics.difference(rendered, standard, in: area).maxAbsolute > 100)
        #expect(Self.differs(rendered, standard, outside: area, in: whole) == 0)
        #expect(ImageMetrics.difference(rendered, sample.input, in: sample.below).maxAbsolute == 0)
    }

    /// `StatusBarSpec` から作った中身は、時刻があれば描き直し、無ければ消す
    @Test
    func convertsFromStatusBarSpec() {
        #expect(PlaySpec.standard == PlaySpec(time: .set("9:41"), cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: 1)))
        #expect(PlaySpec(StatusBarSpec(cellularBars: 2)) == PlaySpec(time: .hide, cellularBars: 2, wifiBars: nil, battery: nil))
    }

    /// 配置を 1 つだけにしたカタログ
    private static func catalog(_ catalog: DeviceCatalog, only layoutID: String) throws -> DeviceCatalog {
        let encoded = try JSONEncoder().encode(catalog)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let layouts = try #require(object["layouts"] as? [[String: Any]])
        object["layouts"] = layouts.filter { $0["id"] as? String == layoutID }
        return try DeviceCatalog(data: JSONSerialization.data(withJSONObject: object))
    }

    /// `area` の外で、2 枚の画像が違っている画素の数
    private static func differs(_ lhs: Bitmap, _ rhs: Bitmap, outside area: PixelRect, in whole: PixelRect) -> Int {
        var count = 0
        for y in whole.y..<whole.maxY {
            for x in whole.x..<whole.maxX where !area.contains(x: x, y: y) && lhs[x, y] != rhs[x, y] {
                count += 1
            }
        }
        return count
    }
}
