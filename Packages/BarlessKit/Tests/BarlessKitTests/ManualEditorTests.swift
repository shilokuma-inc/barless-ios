import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import StatusBarEditor
import Testing

/// 手動調整: 配置（機種）を使わずに、利用者が合わせた帯の高さだけでステータスバーを隠す
struct ManualEditorTests {
    /// 大きさ・世代・文字色が違う代表（単色の背景）
    private static let solidFixtures = [
        "iPhone-SE-3rd-generation__iOS-18-6__light-low",
        "iPhone-11__iOS-27-0__dark-full",
        "iPhone-16__iOS-18-6__light-low",
        "iPhone-17__iOS-27-0__light-low",
        "iPhone-18-Pro-Max__iOS-27-0__dark-full"
    ]

    private struct Sample {
        let fixture: Fixture
        let layout: StatusBarLayout
        let strip: Bitmap
        let editor: ManualEditor

        var scale: Int { fixture.scale }
        /// 利用者が合わせる帯の高さ。インクの下端から 6pt 下
        var bandHeight: Int { layout.inkBottom + 6 * scale }

        /// 上端から `height` 行のうち、画面の左右の端 4pt を除いた範囲
        func band(height: Int) -> PixelRect {
            PixelRect(x: 4 * scale, y: 0, width: strip.width - 8 * scale, height: height)
        }

        /// `height` 行から下
        func below(_ height: Int) -> PixelRect {
            PixelRect(x: 0, y: height, width: strip.width, height: strip.height - height)
        }
    }

    private func sample(_ name: String) throws -> Sample {
        let fixture = try #require(try Fixtures.all().first { $0.name == name }, "\(name) が無い")
        let layout = try #require(fixture.expectedLayout(in: DeviceCatalog.bundled()))
        return Sample(
            fixture: fixture,
            layout: layout,
            strip: try fixture.loadStrip(),
            editor: ManualEditor(pixelWidth: fixture.width, pixelHeight: fixture.height)
        )
    }

    /// 単色の背景: 帯の中は背景の 1 色になり、帯の下は 1 画素も変わらない。帯の高さの合わせ方に幅があっても同じ
    @Test(arguments: solidFixtures)
    func erasesInkOnSolidBackground(name: String) throws {
        let sample = try sample(name)
        let background = Verification.flatBackground(of: sample.strip, scale: sample.scale)
        for extra in [3, 6, 12] {
            let bandHeight = sample.layout.inkBottom + extra * sample.scale

            let result = sample.editor.apply(ManualAdjustment(bandHeight: bandHeight), to: sample.strip)

            #expect(!result.mayLeaveTraces)
            #expect(ImageMetrics.difference(result.bitmap, background, in: sample.band(height: bandHeight)).maxAbsolute == 0)
            #expect(ImageMetrics.difference(result.bitmap, sample.strip, in: sample.below(bandHeight)).maxAbsolute == 0)
        }
    }

    /// 文字の色を指定すると、その明るさのインクだけを消す
    @Test(arguments: [
        ("iPhone-17__iOS-27-0__dark-full", ManualAdjustment.TextColor.white, ManualAdjustment.TextColor.black),
        ("iPhone-16__iOS-18-6__light-low", ManualAdjustment.TextColor.black, ManualAdjustment.TextColor.white)
    ])
    func erasesOnlyInkOfChosenColor(
        name: String, matching: ManualAdjustment.TextColor, opposite: ManualAdjustment.TextColor
    ) throws {
        let sample = try sample(name)
        let background = Verification.flatBackground(of: sample.strip, scale: sample.scale)
        let band = sample.band(height: sample.bandHeight)

        let erased = sample.editor.apply(ManualAdjustment(bandHeight: sample.bandHeight, textColor: matching), to: sample.strip)
        let untouched = sample.editor.apply(ManualAdjustment(bandHeight: sample.bandHeight, textColor: opposite), to: sample.strip)

        #expect(ImageMetrics.difference(erased.bitmap, background, in: band).maxAbsolute == 0)
        #expect(untouched.bitmap.data == sample.strip.data)
    }

    /// 縦のグラデーション: 文字とアイコンだけを消して、背景はほぼ元どおりになる
    @Test
    func erasesInkOnGradient() throws {
        let sample = try sample("iPhone-17__iOS-27-0__dark-full")
        let background = SyntheticBackground.vertical.make(width: sample.strip.width, height: sample.strip.height, isLight: false)
        let input = Synthetic.transplantInk(from: sample.strip, onto: background, scale: sample.scale)

        let result = sample.editor.apply(ManualAdjustment(bandHeight: sample.bandHeight), to: input)

        #expect(!result.mayLeaveTraces)
        #expect(ImageMetrics.difference(result.bitmap, background, in: sample.band(height: sample.bandHeight)).maxAbsolute <= 2)
        #expect(ImageMetrics.difference(result.bitmap, input, in: sample.below(sample.bandHeight)).maxAbsolute == 0)
    }

    /// JPEG で保存し直した画像（SNS を通った画像の代わり）: 文字のまわりのにじみまで消えて、輪郭が薄く残らない。
    /// グラデーションの背景では、消す範囲のすぐ外の色から埋めるので、にじみが残っていると、それが文字の形に広がる
    @Test(arguments: ["iPhone-17__iOS-27-0__light-low", "iPhone-17__iOS-27-0__dark-full", "iPhone-SE-3rd-generation__iOS-18-6__light-low"])
    func erasesRingingOfRecompressedImage(name: String) throws {
        let sample = try sample(name)
        let isLight = sample.fixture.appearance == "light"
        let gradient = SyntheticBackground.vertical.make(width: sample.strip.width, height: sample.strip.height, isLight: isLight)
        let band = sample.band(height: sample.bandHeight)
        for clean in [Verification.flatBackground(of: sample.strip, scale: sample.scale), gradient] {
            let inked = Synthetic.transplantInk(from: sample.strip, onto: clean, scale: sample.scale)
            let input = try Synthetic.recompressed(inked, quality: 0.7)
            let background = try Synthetic.recompressed(clean, quality: 0.7)

            let result = sample.editor.apply(ManualAdjustment(bandHeight: sample.bandHeight), to: input)

            let before = ImageMetrics.difference(input, background, in: band)
            let after = ImageMetrics.difference(result.bitmap, background, in: band)
            #expect(before.maxAbsolute > 100)
            // 広げる幅が 1pt だと、暗いグラデーションで 19 まで残る（2pt では 13 以下）
            #expect(after.maxAbsolute <= 16)
            #expect(after.visibleRatio == 0)
        }
    }

    /// 背景が細かい模様・輪郭が帯を横切る背景では、跡が残りうることを伝える
    @Test
    func flagsBackgroundsThatLeaveTraces() throws {
        let sample = try sample("iPhone-17__iOS-27-0__dark-full")
        let width = sample.strip.width
        let height = sample.strip.height
        let noise = Synthetic.noise(width: width, height: height, base: sample.strip[width / 2, 4 * sample.scale])
        let edge = EdgePlacement.behindBattery.edge(for: sample.layout, timeText: sample.fixture.time)
            .make(width: width, height: height, isLight: false)

        for background in [noise, edge] {
            let input = Synthetic.transplantInk(from: sample.strip, onto: background, scale: sample.scale)
            let result = sample.editor.apply(ManualAdjustment(bandHeight: sample.bandHeight), to: input)
            #expect(result.mayLeaveTraces)
        }
    }

    /// 1 色で塗る: 帯の全体がその色になり、帯の下は変わらない
    @Test
    func fillsBandWithChosenColor() throws {
        let sample = try sample("iPhone-17__iOS-27-0__light-low")
        let color = RGB(red: 12, green: 34, blue: 56)
        let bandHeight = sample.bandHeight

        let result = sample.editor.apply(ManualAdjustment(bandHeight: bandHeight, background: .color(color)), to: sample.strip)

        #expect(!result.mayLeaveTraces)
        let filled = Bitmap(width: sample.strip.width, height: sample.strip.height, fill: color, colorSpace: sample.strip.colorSpace)
        let band = PixelRect(x: 0, y: 0, width: sample.strip.width, height: bandHeight)
        #expect(ImageMetrics.difference(result.bitmap, filled, in: band).maxAbsolute == 0)
        #expect(ImageMetrics.difference(result.bitmap, sample.strip, in: sample.below(bandHeight)).maxAbsolute == 0)
    }

    /// ぼかす: 帯の中から文字の輪郭（となりの画素との大きな差）が無くなり、帯の下は変わらない
    @Test(arguments: ["iPhone-17__iOS-27-0__light-low", "iPhone-SE-3rd-generation__iOS-18-6__light-low"])
    func blursBandUntilShapesDisappear(name: String) throws {
        let sample = try sample(name)
        let bandHeight = sample.bandHeight

        let result = sample.editor.apply(ManualAdjustment(bandHeight: bandHeight, background: .blur), to: sample.strip)

        #expect(!result.mayLeaveTraces)
        #expect(Self.sharpestStep(in: sample.strip, sample.band(height: bandHeight)) > 300)
        #expect(Self.sharpestStep(in: result.bitmap, sample.band(height: bandHeight)) <= 12)
        #expect(ImageMetrics.difference(result.bitmap, sample.strip, in: sample.below(bandHeight)).maxAbsolute == 0)
    }

    /// 上端だけを切り出した画像に当てても、画像の全体に当てても、帯の結果は同じ（調整の途中の表示 = 書き出す画像）
    @Test(arguments: [ManualAdjustment.Background.automatic, .color(RGB(red: 200, green: 30, blue: 30)), .blur])
    func givesSameResultOnStripAndWholeImage(background: ManualAdjustment.Background) throws {
        let sample = try sample("iPhone-17__iOS-27-0__dark-full")
        let strip = sample.strip
        let below = RGB(red: 90, green: 120, blue: 150)
        var whole = Bitmap(width: sample.fixture.width, height: sample.fixture.height, fill: below, colorSpace: strip.colorSpace)
        for y in 0..<strip.height {
            for x in 0..<strip.width {
                whole[x, y] = strip[x, y]
            }
        }
        let adjustment = ManualAdjustment(bandHeight: sample.bandHeight, background: background)

        let fromStrip = sample.editor.apply(adjustment, to: strip).bitmap
        let fromWhole = sample.editor.apply(adjustment, to: whole).bitmap

        #expect(fromWhole.cropped(x: 0, y: 0, width: strip.width, height: strip.height).data == fromStrip.data)
        let rest = PixelRect(x: 0, y: strip.height, width: whole.width, height: whole.height - strip.height)
        #expect(ImageMetrics.difference(fromWhole, whole, in: rest).maxAbsolute == 0)
    }

    /// 最初に出す帯の高さは、どの機種でも、インクの下端から 3pt 以上、下にある。選べる範囲にも入っている
    @Test
    func suggestsBandBelowInkForEveryLayout() throws {
        for layout in try DeviceCatalog.bundled().layouts {
            let editor = ManualEditor(pixelWidth: layout.pixelWidth, pixelHeight: layout.pixelHeight)
            #expect(editor.scale == layout.scale, "\(layout.id)")
            #expect(editor.suggestedBandHeight >= layout.inkBottom + 3 * layout.scale, "\(layout.id)")
            #expect(editor.bandHeightRange.contains(editor.suggestedBandHeight), "\(layout.id)")
            #expect(editor.stripHeight == editor.bandHeightRange.upperBound, "\(layout.id)")
        }
    }

    /// SNS で縮んだ画像（1080×2340 より小さい）・iPad・横長の画像でも、帯の高さを選べる
    @Test(arguments: [(828, 1792), (720, 1560), (2064, 2752), (1920, 1080), (200, 200)])
    func offersBandHeightsForOtherSizes(width: Int, height: Int) {
        let editor = ManualEditor(pixelWidth: width, pixelHeight: height)
        #expect(ManualEditor.supports(pixelWidth: width, pixelHeight: height))
        #expect(editor.bandHeightRange.lowerBound >= 3)
        #expect(editor.bandHeightRange.upperBound < height)
        #expect(editor.bandHeightRange.contains(editor.suggestedBandHeight))
        #expect(editor.clamped(0) == editor.bandHeightRange.lowerBound)
        #expect(editor.clamped(height) == editor.bandHeightRange.upperBound)
    }

    /// 小さすぎる画像と、カメラの写真のような巨大な画像は扱わない
    @Test(arguments: [(120, 300), (8064, 6048), (4097, 1000)])
    func doesNotSupportTinyOrHugeImages(width: Int, height: Int) {
        #expect(!ManualEditor.supports(pixelWidth: width, pixelHeight: height))
    }

    /// 範囲の中で、横にとなり合う画素の色の差（3 チャンネルの合計）の最大
    private static func sharpestStep(in bitmap: Bitmap, _ rect: PixelRect) -> Int {
        var sharpest = 0
        for y in rect.y..<rect.maxY {
            for x in rect.x..<(rect.maxX - 1) {
                sharpest = max(sharpest, bitmap[x, y].distance(to: bitmap[x + 1, y]))
            }
        }
        return sharpest
    }
}
