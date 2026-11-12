import BarlessTestSupport
import CoreGraphics
import DeviceCatalog
import ImageIOKit
import StatusBarAnalyzer
import StatusBarEditor
import Testing

/// 「隠す」の入口（解析 → 消去）を、スクリーンショット全体の大きさの画像で通す
struct StatusBarEditorTests {
    /// 文字認識の代わりに、決まった時刻を返す
    private struct FixedTime: TimeTextRecognizing {
        let time: String?

        func recognizeTimes(in image: CGImage) async throws -> [String] {
            time.map { [$0] } ?? []
        }
    }

    /// 大きさ・世代・文字色が違う代表（単色の背景）
    private static let solidFixtures = [
        "iPhone-SE-3rd-generation__iOS-18-6__light-low",
        "iPhone-11__iOS-27-0__dark-full",
        "iPhone-16__iOS-18-6__light-full",
        "iPhone-17__iOS-27-0__light-low",
        "iPhone-18-Pro-Max__iOS-27-0__dark-full",
        "16ProMax_iOS27.2_std-light_top"
    ]

    private func fixture(named name: String) throws -> Fixture {
        try #require(try Fixtures.all().first { $0.name == name }, "\(name) が無い")
    }

    /// 上端の切り出しの下に、同じ背景の色を足して、スクリーンショット全体の大きさにする
    private func fullSize(_ strip: Bitmap, fixture: Fixture, background: Bitmap? = nil) -> Bitmap {
        let fill = strip[strip.width / 2, 4 * fixture.scale]
        var full = Bitmap(width: fixture.width, height: fixture.height, fill: fill, colorSpace: strip.colorSpace)
        for y in 0..<strip.height {
            for x in 0..<strip.width {
                full[x, y] = strip[x, y]
            }
        }
        if let background {
            for y in strip.height..<min(full.height, background.height) {
                for x in 0..<min(full.width, background.width) {
                    full[x, y] = background[x, y]
                }
            }
        }
        return full
    }

    @Test(arguments: solidFixtures)
    func hidesStatusBarOnSolidBackground(name: String) async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: name)
        let strip = try fixture.loadStrip()
        let input = fullSize(strip, fixture: fixture)
        let editor = StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: fixture.time))

        let result = try await editor.hide(input.makeCGImage())

        let hidden = try #require(result.hidden, "\(fixture): \(result.outcome)")
        let layout = try #require(fixture.expectedLayout(in: catalog))
        #expect(hidden.layout.id == layout.id)
        #expect(hidden.background == .solid)
        #expect(!hidden.mayLeaveTraces)
        #expect(hidden.bandHeight == layout.inkTop + layout.inkBottom)
        // 帯の中は背景の色だけになり、帯の外は 1 画素も変わらない
        let output = try Bitmap(cgImage: result.image)
        #expect(output.width == fixture.width && output.height == fixture.height)
        let background = Verification.flatBackground(of: input, scale: fixture.scale)
        let band = Verification.band(of: layout)
        #expect(ImageMetrics.difference(output, background, in: band).maxAbsolute == 0)
        let below = PixelRect(x: 0, y: band.maxY, width: input.width, height: input.height - band.maxY)
        #expect(ImageMetrics.difference(output, input, in: below).maxAbsolute == 0)
    }

    /// 文字認識も含めて通す（Vision を使うので 1 枚だけ）
    @Test
    func hidesStatusBarWithTextRecognition() async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: "iPhone-17__iOS-27-0__dark-full")
        let input = fullSize(try fixture.loadStrip(), fixture: fixture)

        let result = try await StatusBarEditor(catalog: catalog).hide(input.makeCGImage())

        #expect(result.hidden?.layout.id == fixture.expectedLayout(in: catalog)?.id)
    }

    /// 背景が細かい模様のときも消すが、跡が残りうることを伝える
    @Test
    func flagsComplexBackground() async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try fixture(named: "iPhone-17__iOS-27-0__dark-full")
        let strip = try fixture.loadStrip()
        let noise = Self.noise(width: fixture.width, height: fixture.height, base: strip[strip.width / 2, 4 * fixture.scale])
        let noisyTop = noise.cropped(x: 0, y: 0, width: strip.width, height: strip.height)
        let noisyStrip = Synthetic.transplantInk(from: strip, onto: noisyTop, scale: fixture.scale)
        let input = fullSize(noisyStrip, fixture: fixture, background: noise)
        let editor = StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: fixture.time))

        let result = try await editor.hide(input.makeCGImage())

        let hidden = try #require(result.hidden, "\(result.outcome)")
        #expect(hidden.layout.id == fixture.expectedLayout(in: catalog)?.id)
        #expect(hidden.background == .complex)
        #expect(hidden.mayLeaveTraces)
    }

    /// カタログに無い大きさ・対象外の機種・ステータスバーが無い画像は、元の画像のまま返す
    @Test(arguments: [
        (1000, 2000, HideFailure.unknownSize),
        (1398, 2034, HideFailure.unsupportedScreen),
        (1206, 2622, HideFailure.undetermined)
    ])
    func keepsImageWhenStatusBarCannotBeLocated(width: Int, height: Int, expected: HideFailure) async throws {
        let catalog = try DeviceCatalog.bundled()
        let input = Bitmap(width: width, height: height, fill: RGB(red: 240, green: 240, blue: 244))
        let image = try input.makeCGImage()

        let result = try await StatusBarEditor(catalog: catalog, recognizer: FixedTime(time: nil)).hide(image)

        #expect(result.outcome == .notHidden(expected))
        #expect(result.hidden == nil)
        #expect(result.image === image)
    }

    /// 大きさだけで消せないと分かる画像は、画素を展開する前に理由が分かる
    @Test(arguments: [
        (1000, 2000, HideFailure.unknownSize),
        (8064, 6048, HideFailure.unknownSize),
        (1398, 2034, HideFailure.unsupportedScreen)
    ])
    func tellsFailureFromSizeAlone(width: Int, height: Int, expected: HideFailure) throws {
        let editor = StatusBarEditor(catalog: try DeviceCatalog.bundled())
        #expect(editor.failureKnownFromSize(pixelWidth: width, pixelHeight: height) == expected)
    }

    /// 対応している大きさは、解析するまで分からない
    @Test
    func cannotTellFromSizeForSupportedScreens() throws {
        let catalog = try DeviceCatalog.bundled()
        let editor = StatusBarEditor(catalog: catalog)
        for layout in catalog.layouts {
            #expect(editor.failureKnownFromSize(pixelWidth: layout.pixelWidth, pixelHeight: layout.pixelHeight) == nil)
        }
    }

    /// 背景の色のまわりで、画素ごとに少しずつ色が揺れる画像（写真や模様の代わり）
    private static func noise(width: Int, height: Int, base: RGB) -> Bitmap {
        var bitmap = Bitmap(width: width, height: height, fill: base)
        var state: UInt32 = 20_261_112
        func next() -> Int {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state >> 24) % 17 - 8
        }
        func shift(_ value: UInt8) -> UInt8 {
            UInt8(min(255, max(0, Int(value) + next())))
        }
        for y in 0..<height {
            for x in 0..<width {
                bitmap[x, y] = RGB(red: shift(base.red), green: shift(base.green), blue: shift(base.blue))
            }
        }
        return bitmap
    }
}
