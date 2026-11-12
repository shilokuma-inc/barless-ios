@testable import Barless
import CoreGraphics
import Foundation
import ImageIOKit
import StatusBarEditor
import Testing

/// 画像を選んでから結果が出るまでの状態
@MainActor
struct EditSessionTests {
    /// 呼ばれた回数を数え、決まった結果を返す
    private actor StubProcessor: ScreenshotProcessing {
        private(set) var callCount = 0
        private let result: Result<EditedScreenshot, any Error>

        init(result: Result<EditedScreenshot, any Error>) {
            self.result = result
        }

        func process(imageData: Data) async throws -> EditedScreenshot {
            callCount += 1
            return try result.get()
        }
    }

    private func screenshot() throws -> EditedScreenshot {
        let image = try Bitmap(width: 4, height: 4).makeCGImage()
        return EditedScreenshot(before: image, after: image, tidied: nil, outcome: .notHidden(.unknownSize))
    }

    @Test
    func becomesReadyWhenHidingFinishes() async throws {
        let processor = StubProcessor(result: .success(try screenshot()))
        let session = EditSession(source: { Data([1, 2, 3]) }, processor: processor)

        await session.start()

        guard case let .ready(result) = session.phase else {
            Issue.record("ready になっていない: \(session.phase)")
            return
        }
        #expect(result.outcome == .notHidden(.unknownSize))
        #expect(await processor.callCount == 1)
    }

    @Test
    func failsWhenImageCannotBeLoaded() async throws {
        let processor = StubProcessor(result: .success(try screenshot()))
        let session = EditSession(source: { nil }, processor: processor)

        await session.start()

        guard case .failed = session.phase else {
            Issue.record("failed になっていない: \(session.phase)")
            return
        }
        #expect(await processor.callCount == 0)
    }

    @Test
    func failsWhenHidingThrows() async {
        let session = EditSession(source: { Data([1]) }, processor: StubProcessor(result: .failure(ImageCodecError.cannotDecode)))

        await session.start()

        guard case .failed = session.phase else {
            Issue.record("failed になっていない: \(session.phase)")
            return
        }
    }

    /// 画面が出るたびに呼ばれても、解析は 1 回だけ
    @Test
    func startsOnlyOnce() async throws {
        let processor = StubProcessor(result: .success(try screenshot()))
        let session = EditSession(source: { Data([1]) }, processor: processor)

        await session.start()
        await session.start()

        #expect(await processor.callCount == 1)
    }
}

/// 実際の解析と消去を、アプリの中で通す
struct ScreenshotProcessorTests {
    /// 作り物のスクリーンショット（撮影モードと UI テストで使う）のステータスバーを、正しい配置として消せる
    @Test
    func hidesStatusBarOfSampleScreenshot() async throws {
        let result = try await ScreenshotProcessor().process(imageData: SampleScreenshot.pngData())

        let hidden = try #require(result.hidden, "\(result.outcome)")
        #expect(hidden.layout.id == SampleScreenshot.layoutID)
        #expect(!hidden.mayLeaveTraces)
        #expect(result.after.width == result.before.width && result.after.height == result.before.height)
        // 時刻があった場所が、背景の色に戻っている
        let before = try Bitmap(cgImage: result.before)
        let after = try Bitmap(cgImage: result.after)
        let background = after[after.width / 2, 12]
        let band = (0..<hidden.bandHeight).flatMap { y in (12..<(after.width - 12)).map { (x: $0, y: y) } }
        #expect(band.contains { before[$0.x, $0.y] != background })
        #expect(band.allSatisfy { after[$0.x, $0.y] == background })
    }

    /// 「整える」の画像には、描き直したステータスバーが載っている。「隠す」の画像とは別に持つ
    @Test
    func tidiesStatusBarOfSampleScreenshot() async throws {
        let result = try await ScreenshotProcessor().process(imageData: SampleScreenshot.pngData())

        let hidden = try #require(result.hidden, "\(result.outcome)")
        let tidied = try Bitmap(cgImage: try #require(result.tidied))
        let after = try Bitmap(cgImage: result.after)
        #expect(tidied.width == after.width && tidied.height == after.height)
        let band = (0..<hidden.bandHeight).flatMap { y in (12..<(after.width - 12)).map { (x: $0, y: y) } }
        #expect(band.contains { tidied[$0.x, $0.y] != after[$0.x, $0.y] })
        // 帯の下は「隠す」と同じ
        let rowsBelow = hidden.bandHeight..<(hidden.bandHeight + 200)
        #expect(rowsBelow.allSatisfy { tidied[tidied.width / 2, $0] == after[after.width / 2, $0] })
        // モードごとの画像
        #expect(result.image(for: .hide) === result.after)
        #expect(result.image(for: .tidy) === result.tidied)
    }

    /// 対応していない大きさ・対象外の機種の画像は、消さずに、縮めた画像を画面用に返す
    @Test(arguments: [
        (3000, 400, HideFailure.unknownSize),
        (1398, 2034, HideFailure.unsupportedScreen)
    ])
    func returnsPreviewWhenSizeIsNotSupported(width: Int, height: Int, expected: HideFailure) async throws {
        let data = try ImageEncoder.encode(Bitmap(width: width, height: height).makeCGImage())

        let result = try await ScreenshotProcessor().process(imageData: data)

        #expect(result.outcome == .notHidden(expected))
        #expect(result.hidden == nil)
        #expect(result.tidied == nil)
        // 消せなかった画像は、どのモードでも同じ画像を出す
        #expect(result.image(for: .tidy) === result.after)
        #expect(max(result.after.width, result.after.height) == min(max(width, height), ScreenshotProcessor.previewMaxPixelSize))
        #expect(result.before === result.after)
    }

    @Test
    func throwsForBrokenData() async {
        await #expect(throws: ImageCodecError.cannotDecode) {
            try await ScreenshotProcessor().process(imageData: Data([0, 1, 2, 3]))
        }
    }
}
