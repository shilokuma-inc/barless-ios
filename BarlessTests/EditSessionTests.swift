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
    private actor StubHider: ScreenshotHiding {
        private(set) var callCount = 0
        private let result: Result<EditedScreenshot, any Error>

        init(result: Result<EditedScreenshot, any Error>) {
            self.result = result
        }

        func hide(imageData: Data) async throws -> EditedScreenshot {
            callCount += 1
            return try result.get()
        }
    }

    private func screenshot() throws -> EditedScreenshot {
        let image = try Bitmap(width: 4, height: 4).makeCGImage()
        return EditedScreenshot(before: image, after: image, outcome: .notHidden(.unknownSize))
    }

    @Test
    func becomesReadyWhenHidingFinishes() async throws {
        let hider = StubHider(result: .success(try screenshot()))
        let session = EditSession(source: { Data([1, 2, 3]) }, hider: hider)

        await session.start()

        guard case let .ready(result) = session.phase else {
            Issue.record("ready になっていない: \(session.phase)")
            return
        }
        #expect(result.outcome == .notHidden(.unknownSize))
        #expect(await hider.callCount == 1)
    }

    @Test
    func failsWhenImageCannotBeLoaded() async throws {
        let hider = StubHider(result: .success(try screenshot()))
        let session = EditSession(source: { nil }, hider: hider)

        await session.start()

        guard case .failed = session.phase else {
            Issue.record("failed になっていない: \(session.phase)")
            return
        }
        #expect(await hider.callCount == 0)
    }

    @Test
    func failsWhenHidingThrows() async {
        let session = EditSession(source: { Data([1]) }, hider: StubHider(result: .failure(ImageCodecError.cannotDecode)))

        await session.start()

        guard case .failed = session.phase else {
            Issue.record("failed になっていない: \(session.phase)")
            return
        }
    }

    /// 画面が出るたびに呼ばれても、解析は 1 回だけ
    @Test
    func startsOnlyOnce() async throws {
        let hider = StubHider(result: .success(try screenshot()))
        let session = EditSession(source: { Data([1]) }, hider: hider)

        await session.start()
        await session.start()

        #expect(await hider.callCount == 1)
    }
}

/// 実際の解析と消去を、アプリの中で通す
struct StatusBarHiderTests {
    /// 作り物のスクリーンショット（撮影モードと UI テストで使う）のステータスバーを、正しい配置として消せる
    @Test
    func hidesStatusBarOfSampleScreenshot() async throws {
        let result = try await StatusBarHider().hide(imageData: SampleScreenshot.pngData())

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

    /// 対応していない大きさの画像は、消さずに、縮めた画像を画面用に返す
    @Test
    func returnsPreviewWhenSizeIsUnknown() async throws {
        let large = try ImageEncoder.encode(Bitmap(width: 3000, height: 400).makeCGImage())

        let result = try await StatusBarHider().hide(imageData: large)

        #expect(result.outcome == .notHidden(.unknownSize))
        #expect(result.hidden == nil)
        #expect(result.after.width == StatusBarHider.previewMaxPixelSize)
        #expect(result.before === result.after)
    }

    @Test
    func throwsForBrokenData() async {
        await #expect(throws: ImageCodecError.cannotDecode) {
            try await StatusBarHider().hide(imageData: Data([0, 1, 2, 3]))
        }
    }
}
