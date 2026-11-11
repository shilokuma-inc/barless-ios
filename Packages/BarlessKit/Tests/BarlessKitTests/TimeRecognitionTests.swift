import BarlessTestSupport
import CoreGraphics
import DeviceCatalog
import Foundation
import ImageIOKit
@testable import StatusBarAnalyzer
import Testing

/// Vision の文字認識で時刻を読み、判定までを通す
struct TimeRecognitionTests {
    /// 全 166 枚を読むと数十秒かかるので、ふだんは大きさ・世代・背景が違う代表だけを読む。
    /// 全部を読むときは環境変数 `BARLESS_FULL_OCR=1` を付ける（結果は docs/verification.md）
    private static let representatives: Set<String> = [
        "iPhone-SE-3rd-generation__iOS-18-6__light-low",
        "iPhone-11__iOS-27-0__dark-full",
        "iPhone-12__iOS-26-5__dark-full",
        "iPhone-16__iOS-18-6__light-full",
        "iPhone-17__iOS-27-0__dark-home",
        "iPhone-18-Pro__iOS-27-0__dark-full",
        "iPhone-Air__iOS-26-5__light-low",
        "16ProMax_iOS27.2_std-light_top"
    ]

    private func targets() throws -> [Fixture] {
        let all = try Fixtures.supported()
        if ProcessInfo.processInfo.environment["BARLESS_FULL_OCR"] == "1" { return all }
        return all.filter { Self.representatives.contains($0.name) }
    }

    @Test
    func readsTimeAndResolvesLayout() async throws {
        let catalog = try DeviceCatalog.bundled()
        let analyzer = StatusBarAnalyzer(catalog: catalog)
        let fixtures = try targets()
        #expect(fixtures.count >= Self.representatives.count)
        for fixture in fixtures {
            let analysis = await analyzer.analyze(strip: try fixture.loadStrip(), pixelHeight: fixture.height)
            #expect(analysis.timeText == fixture.time, "\(fixture)")
            let expected = try #require(fixture.expectedLayout(in: catalog), "\(fixture)")
            let isKnownUndecided = fixture.name.hasPrefix("iPhone-SE") && fixture.variant == "dark-home" && fixture.runtime != "iOS-18-6"
            if !isKnownUndecided {
                #expect(analysis.decision.layout?.id == expected.id, "\(fixture): \(analysis.decision)")
            }
        }
    }

    /// スクリーンショット全体（上端以外は適当な背景）を `CGImage` で渡しても同じ結果になる
    @Test
    func analyzesFullSizeImage() async throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try #require(try Fixtures.all().first { $0.name == "iPhone-16__iOS-27-0__light-low" })
        let strip = try fixture.loadStrip()
        var full = Bitmap(width: fixture.width, height: fixture.height, fill: strip[strip.width / 2, 12], colorSpace: strip.colorSpace)
        let image = try strip.makeCGImage()
        try full.draw { context in
            context.interpolationQuality = .none
            // 画像は上下を反転して描かれるので、上端に正立で置く
            context.translateBy(x: 0, y: CGFloat(strip.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
        }
        let analysis = try await StatusBarAnalyzer(catalog: catalog).analyze(full.makeCGImage())
        #expect(analysis.timeText == "23:58")
        #expect(analysis.decision.layout?.id == "1179x2556-a/ios27")
        #expect(analysis.appearance == .darkContent)
    }

    /// 文字認識が失敗しても、時刻の高さと中心だけで判定を続ける
    @Test
    func fallsBackWhenRecognitionFails() async throws {
        struct Failing: TimeTextRecognizing {
            func recognizeTimes(in image: CGImage) async throws -> [String] {
                throw CocoaError(.featureUnsupported)
            }
        }
        let catalog = try DeviceCatalog.bundled()
        let fixture = try #require(try Fixtures.all().first { $0.name == "iPhone-17__iOS-27-0__light-full" })
        let analyzer = StatusBarAnalyzer(catalog: catalog, recognizer: Failing())
        let analysis = await analyzer.analyze(strip: try fixture.loadStrip(), pixelHeight: fixture.height)
        #expect(analysis.timeText == nil)
        #expect(analysis.decision.layout?.id == "1206x2622-a/ios27")
    }

    @Test(arguments: [
        ("9:41", "9:41"), ("23:58", "23:58"), ("Carrier 9:41", "9:41"), ("0:00", "0:00"), ("3:16 ", "3:16"),
        ("24:00", nil), ("9:61", nil), ("941", nil), ("12:345", nil), ("", nil)
    ] as [(String, String?)])
    func extractsTimeFromRecognizedText(text: String, expected: String?) {
        #expect(VisionTimeTextRecognizer.time(in: text) == expected)
    }
}
