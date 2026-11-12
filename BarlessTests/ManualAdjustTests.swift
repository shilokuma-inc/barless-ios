@testable import Barless
import CoreGraphics
import Foundation
import ImageIOKit
import StatusBarEditor
import Testing

/// 自動で消せなかった画像から、手動調整へ進めるか
struct ManualSourceTests {
    /// 大きさが変わったスクリーンショットは、自動では消せないが、手動調整へ進める
    @Test
    func offersManualAdjustForResavedScreenshot() async throws {
        let data = try SampleScreenshot.resavedPNGData()

        let result = try await ScreenshotProcessor().process(imageData: data)

        #expect(result.outcome == .notHidden(.unknownSize))
        #expect(!result.hasResult)
        #expect(result.bandHeight == nil)
        #expect(result.manual == nil)
        #expect(result.manualSource?.imageData == data)
    }

    /// カメラの写真のような巨大な画像と、小さすぎる画像は、手動調整の対象にしない
    @Test(arguments: [(4200, 300), (150, 600)])
    func doesNotOfferManualAdjustForUnsupportedSizes(width: Int, height: Int) async throws {
        let data = try ImageEncoder.encode(Bitmap(width: width, height: height).makeCGImage())

        let result = try await ScreenshotProcessor().process(imageData: data)

        #expect(result.outcome == .notHidden(.unknownSize))
        #expect(result.manualSource == nil)
    }

    /// 自動で消せた画像には、手動調整の元データを持たせない
    @Test
    func doesNotKeepManualSourceWhenHidden() async throws {
        let result = try await ScreenshotProcessor().process(imageData: SampleScreenshot.pngData())

        #expect(result.hidden != nil)
        #expect(result.manualSource == nil)
    }
}

/// 手動調整の画面の状態
@MainActor
struct ManualAdjustModelTests {
    /// 作り物のスクリーンショットの背景の色
    private static let background = RGB(red: 246, green: 246, blue: 248)

    private func model() throws -> ManualAdjustModel {
        ManualAdjustModel(source: ManualSource(imageData: try SampleScreenshot.resavedPNGData()), outcome: .notHidden(.unknownSize))
    }

    private func canvas(of model: ManualAdjustModel) throws -> ManualCanvas {
        guard case let .ready(canvas) = model.phase else {
            throw ImageCodecError.cannotDecode
        }
        return canvas
    }

    /// 読み込むと、帯の高さの見込みが入り、その調整を当てた途中の結果ができる
    @Test
    func loadsImageAndRendersPreview() async throws {
        let model = try model()

        await model.start()
        await model.waitForPreview()

        let canvas = try canvas(of: model)
        #expect(canvas.original.width == 900)
        #expect(model.bandHeight == canvas.editor.suggestedBandHeight)
        #expect(model.adjustment == ManualAdjustment(bandHeight: model.bandHeight))
        let preview = try #require(model.preview)
        #expect(preview.strip.width == 900 && preview.strip.height == canvas.editor.stripHeight)
        #expect(!preview.mayLeaveTraces)
        // 途中の結果では、帯の中が背景の色に戻っている。元の切り出しには、文字とアイコンが写っている
        let strip = try Bitmap(cgImage: preview.strip)
        let band = (0..<model.bandHeight).flatMap { y in (12..<888).map { (x: $0, y: y) } }
        #expect(band.contains { canvas.strip[$0.x, $0.y] != Self.background })
        #expect(band.allSatisfy { strip[$0.x, $0.y] == Self.background })
    }

    /// 読み込めないデータなら、失敗になる
    @Test
    func failsForBrokenData() async {
        let model = ManualAdjustModel(source: ManualSource(imageData: Data([1, 2, 3])), outcome: .notHidden(.unknownSize))

        await model.start()

        guard case .failed = model.phase else {
            Issue.record("failed になっていない: \(model.phase)")
            return
        }
        #expect(await model.finish() == nil)
    }

    /// 帯の高さは、選べる範囲に収める
    @Test
    func clampsBandHeight() async throws {
        let model = try model()
        await model.start()
        let range = try canvas(of: model).editor.bandHeightRange

        model.setBandHeight(0)
        #expect(model.bandHeight == range.lowerBound)
        model.setBandHeight(100_000)
        #expect(model.bandHeight == range.upperBound)
    }

    /// 「色を拾う」を選ぶと、まず帯のすぐ下の色になり、画像の色を拾うとその色で帯を塗る
    @Test
    func picksFillColorFromImage() async throws {
        let model = try model()
        await model.start()
        let canvas = try canvas(of: model)

        // 「色を拾う」を選ぶ前は、拾えない
        model.pickColor(x: 100, y: 220)
        #expect(model.pickedColor == nil)

        model.setBackgroundMode(.pickColor)
        #expect(model.pickedColor == Self.background)

        // 上端の切り出しの外（画像の下のほう）からも拾える。画像の外は無視する
        let whole = try Bitmap(cgImage: canvas.original)
        let low = (x: 450, y: canvas.original.height - 40)
        #expect(low.y >= canvas.strip.height)
        model.pickColor(x: low.x, y: low.y)
        #expect(model.pickedColor == whole[low.x, low.y])
        model.pickColor(x: -1, y: 5000)
        #expect(model.pickedColor == whole[low.x, low.y])

        // 見出しに見立てた濃い線の色で、帯の全体を塗る
        let headline = (x: 100, y: 220)
        model.pickColor(x: headline.x, y: headline.y)
        let picked = try #require(model.pickedColor)
        #expect(picked == whole[headline.x, headline.y] && picked != Self.background)
        #expect(model.adjustment.background == .color(picked))
        await model.waitForPreview()
        let strip = try Bitmap(cgImage: try #require(model.preview).strip)
        #expect((0..<model.bandHeight).allSatisfy { strip[450, $0] == picked })
        #expect(strip[450, model.bandHeight] == canvas.strip[450, model.bandHeight])
    }

    /// 「この設定で続ける」: 画像の全体に調整を当てた結果になる。帯の下は変わらない
    @Test
    func finishesWithWholeImage() async throws {
        let model = try model()
        await model.start()
        model.setTextColor(.black)

        let result = try #require(await model.finish())

        let manual = try #require(result.manual)
        #expect(manual.adjustment == ManualAdjustment(bandHeight: model.bandHeight, textColor: .black))
        #expect(!manual.mayLeaveTraces)
        #expect(result.hasResult)
        #expect(result.bandHeight == model.bandHeight)
        #expect(result.outcome == .notHidden(.unknownSize))
        #expect(result.tidied == nil)
        #expect(result.manualSource != nil)
        // 「整える」を選んでいても、手動調整の結果では「隠す」の画像を出す
        #expect(result.image(for: .tidy) === result.after)
        let before = try Bitmap(cgImage: result.before)
        let after = try Bitmap(cgImage: result.after)
        #expect(after.width == 900 && after.height == before.height)
        let band = (0..<model.bandHeight).flatMap { y in (12..<888).map { (x: $0, y: y) } }
        #expect(band.contains { before[$0.x, $0.y] != Self.background })
        #expect(band.allSatisfy { after[$0.x, $0.y] == Self.background })
        let rowsBelow = model.bandHeight..<after.height
        #expect(rowsBelow.allSatisfy { y in stride(from: 0, to: 900, by: 7).allSatisfy { after[$0, y] == before[$0, y] } })
    }

    /// 「続ける」の処理の途中は、調整を変えない（書き出す結果と、画面に残る調整が同じになる）
    @Test
    func ignoresChangesWhileFinishing() async throws {
        let model = try model()
        await model.start()
        let before = model.adjustment

        let finishing = Task { await model.finish() }
        for _ in 0..<1000 where !model.isFinishing {
            await Task.yield()
        }
        #expect(model.isFinishing)
        model.setBandHeight(before.bandHeight + 30)
        model.setTextColor(.white)
        model.setBackgroundMode(.blur)
        model.pickColor(x: 10, y: 10)
        let result = try #require(await finishing.value)

        #expect(model.adjustment == before)
        #expect(result.manual?.adjustment == before)
        #expect(!model.isFinishing)
        // 終わった後は、また変えられる
        model.setBackgroundMode(.blur)
        #expect(model.adjustment.background == .blur)
    }

    /// 処理の途中で調整の画面から戻ったら、処理が終わっても、その結果は使わない
    @Test
    func discardsResultWhenCancelledWhileFinishing() async throws {
        let model = try model()
        await model.start()

        let finishing = Task { await model.finish() }
        for _ in 0..<1000 where !model.isFinishing {
            await Task.yield()
        }
        #expect(model.isFinishing)
        model.cancelFinish()

        #expect(await finishing.value == nil)
        #expect(!model.isFinishing)
        // 取り消した後に、もう一度続ければ、結果が出る
        #expect(await model.finish() != nil)
    }

    /// 調整し直すとき（画面を出し直したとき）に、前の調整が残っている
    @Test
    func keepsAdjustmentWhenStartedAgain() async throws {
        let model = try model()
        await model.start()
        model.setBandHeight(model.bandHeight + 20)
        model.setBackgroundMode(.blur)
        let adjusted = model.adjustment

        await model.start()

        #expect(model.adjustment == adjusted)
        #expect(adjusted.background == .blur)
    }
}

/// 手動調整の結果を、編集の結果として受け取る
@MainActor
struct EditSessionManualTests {
    private struct FixedProcessor: ScreenshotProcessing {
        let result: EditedScreenshot

        func process(imageData: Data) async throws -> EditedScreenshot { result }
    }

    @Test
    func replacesResultWithManualEdit() async throws {
        let image = try Bitmap(width: 4, height: 4).makeCGImage()
        let failed = EditedScreenshot(before: image, after: image, tidied: nil, outcome: .notHidden(.unknownSize))
        var adjusted = failed
        adjusted.manual = ManualEdit(adjustment: ManualAdjustment(bandHeight: 2), mayLeaveTraces: false)
        let session = EditSession(source: { Data([1]) }, processor: FixedProcessor(result: failed))

        // 読み込みが終わる前は、受け取らない
        session.apply(adjusted)
        guard case .loading = session.phase else {
            Issue.record("loading のままになっていない: \(session.phase)")
            return
        }

        await session.start()
        session.apply(adjusted)

        guard case let .ready(result) = session.phase else {
            Issue.record("ready になっていない: \(session.phase)")
            return
        }
        #expect(result.manual == adjusted.manual)
        #expect(result.hasResult)
    }
}
