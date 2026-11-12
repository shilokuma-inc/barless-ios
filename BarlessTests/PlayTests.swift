@testable import Barless
import CoreGraphics
import Foundation
import ImageIOKit
import StatusBarEditor
import StatusBarRenderer
import Testing

/// 時刻の文字列は、地域の書き方に合わせる（午前・午後は付けない）
struct PlayTimeTests {
    @Test(arguments: [
        ("en_US", 9, 41, "9:41"),
        ("en_US", 14, 8, "2:08"),
        ("en_US", 0, 5, "12:05"),
        ("ja_JP", 9, 41, "9:41"),
        ("ja_JP", 14, 8, "14:08"),
        ("ja_JP", 0, 5, "0:05"),
        ("en_GB", 9, 41, "09:41"),
        ("en_GB", 23, 59, "23:59")
    ])
    func formatsTimeForLocale(identifier: String, hour: Int, minute: Int, expected: String) {
        #expect(PlayTime.text(hour: hour, minute: minute, locale: Locale(identifier: identifier)) == expected)
    }
}

/// 「遊ぶ」の状態
@MainActor
struct PlayModelTests {
    private struct Sample {
        let screenshot: EditedScreenshot
        let model: PlayModel
    }

    /// 作り物のスクリーンショット（iPhone 17・iOS 27）を解析して、「遊ぶ」の状態を作る
    /// - Parameters:
    ///   - used: 無料の回数を、今日すでに使ったことにする数
    ///   - isPro: Pro として扱うか
    private func sample(locale: String = "ja_JP", used: Int = 0, isPro: Bool = false) async throws -> Sample {
        let screenshot = try await ScreenshotProcessor().process(imageData: SampleScreenshot.pngData())
        let composer = try #require(screenshot.composer)
        let tidied = try #require(screenshot.tidied)
        let allowance = PlayAllowance(store: InMemoryPlayUsageStore(count: used), proStatus: FixedPlan(isPro: isPro))
        let model = PlayModel(
            composer: composer, initialImage: tidied, allowance: allowance, watermark: "Barless", locale: Locale(identifier: locale)
        )
        return Sample(screenshot: screenshot, model: model)
    }

    /// 決まった答えを返す、Pro かどうかの判定
    nonisolated private struct FixedPlan: ProStatusProviding {
        let isPro: Bool
    }

    /// 画像の右下（透かしが入るあたり）で、2 枚の画像が違っているか
    private func differsInBottomRight(_ lhs: CGImage, _ rhs: CGImage) throws -> Bool {
        let left = try Bitmap(cgImage: lhs)
        let right = try Bitmap(cgImage: rhs)
        let rows = (left.height - 120)..<left.height
        let columns = (left.width * 2 / 3)..<left.width
        return rows.contains { y in columns.contains { left[$0, y] != right[$0, y] } }
    }

    /// 帯の中で、2 枚の画像が違っている画素の、左端と右端（違いが無ければ `nil`）
    private func changedColumns(_ lhs: CGImage, _ rhs: CGImage, bandHeight: Int) throws -> ClosedRange<Int>? {
        let left = try Bitmap(cgImage: lhs)
        let right = try Bitmap(cgImage: rhs)
        let columns = (0..<left.width).filter { x in (0..<bandHeight).contains { left[x, $0] != right[x, $0] } }
        guard let first = columns.first, let last = columns.last else { return nil }
        return first...last
    }

    /// 最初の中身は「整える」と同じで、画像も「整える」の結果をそのまま使う
    @Test
    func startsFromTidiedImage() async throws {
        let sample = try await sample()

        #expect(sample.model.spec == .standard)
        #expect(sample.model.timeText == "9:41")
        #expect(sample.model.canKeepTime && sample.model.canDrawWiFi)
        #expect(sample.model.image === sample.screenshot.tidied)
        // 「遊ぶ」で値を変える前の画像は、「整える」と同じ
        #expect(sample.screenshot.image(for: .play) === sample.screenshot.tidied)
    }

    /// 値を変えると、その中身で描き直した画像になる。変わるのは、その要素のあたりだけ
    @Test
    func rendersImageWhenValuesChange() async throws {
        let sample = try await sample()
        let model = sample.model
        let tidied = try #require(sample.screenshot.tidied)
        let bandHeight = try #require(sample.screenshot.bandHeight)

        model.setBatteryPercent(40)
        await model.waitForRender()

        #expect(model.spec.battery == BatterySpec(level: 0.4))
        #expect(model.image !== tidied)
        // 電池は右端にある。左半分（時刻）は変わらない
        let battery = try #require(try changedColumns(model.image, tidied, bandHeight: bandHeight))
        #expect(battery.lowerBound > tidied.width * 3 / 4)

        model.setTimeChoice(.hide)
        model.setCellularBars(1)
        model.setWiFiBars(nil)
        await model.waitForRender()

        #expect(model.spec == PlaySpec(time: .hide, cellularBars: 1, wifiBars: nil, battery: BatterySpec(level: 0.4)))
        let all = try #require(try changedColumns(model.image, tidied, bandHeight: bandHeight))
        #expect(all.lowerBound < tidied.width / 4)
        // 帯の下は、元の画像のまま（右下の透かしが入るあたりを除く）
        let before = try Bitmap(cgImage: sample.screenshot.before)
        let after = try Bitmap(cgImage: model.image)
        let columns = stride(from: 0, to: after.width, by: 7)
        #expect((bandHeight..<(after.height - 120)).allSatisfy { y in columns.allSatisfy { after[$0, y] == before[$0, y] } })
        #expect(try differsInBottomRight(model.image, sample.screenshot.before))
    }

    /// 無料では、値を変えた画像にだけ透かしが入る。値を戻すと、透かしも消える
    @Test
    func addsWatermarkOnlyToCustomizedImages() async throws {
        let sample = try await sample()
        let model = sample.model
        let tidied = try #require(sample.screenshot.tidied)

        model.setBatteryPercent(40)
        await model.waitForRender()
        #expect(model.isCustomized)
        #expect(try differsInBottomRight(model.image, tidied))

        // 「そのまま」「隠す」「オフ」は、自由な値に数えない
        model.setBatteryPercent(100)
        model.setTimeChoice(.hide)
        model.setWiFiBars(nil)
        await model.waitForRender()
        #expect(!model.isCustomized)
        #expect(try !differsInBottomRight(model.image, tidied))
    }

    /// Pro では、値を変えても透かしが入らず、回数も使わない
    @Test
    func proHasNoWatermarkAndNoLimit() async throws {
        let sample = try await sample(used: 3, isPro: true)
        let model = sample.model
        let tidied = try #require(sample.screenshot.tidied)

        model.setBatteryPercent(40)
        await model.waitForRender()

        #expect(try !differsInBottomRight(model.image, tidied))
        #expect(model.canExport && !model.usesAllowanceOnExport)
        model.markExported()
        #expect(model.allowance.usedToday == 3)
    }

    /// 無料の回数を使い切っていると、値を変えた画像は書き出せない。値を変えていない画像は書き出せる
    @Test
    func cannotExportCustomizedImageWhenAllowanceIsUsedUp() async throws {
        let model = try await sample(used: 3).model

        #expect(model.canExport)
        model.setCellularBars(2)
        #expect(model.usesAllowanceOnExport)
        #expect(!model.canExport)
        model.setCellularBars(4)
        #expect(model.canExport)
    }

    /// 書き出すと、無料の回数を 1 回使う。同じ中身をもう一度書き出しても、使わない
    @Test
    func usesAllowanceOncePerExportedSpec() async throws {
        let model = try await sample().model

        // 値を変えていない画像は、回数を使わない
        model.markExported()
        #expect(model.allowance.remainingToday == 3)

        model.setBatteryPercent(40)
        #expect(model.usesAllowanceOnExport)
        model.markExported()
        #expect(model.allowance.remainingToday == 2)
        #expect(!model.usesAllowanceOnExport)
        model.markExported()
        #expect(model.allowance.remainingToday == 2)

        // 値を変えたら、また 1 回使う
        model.setBatteryPercent(41)
        #expect(model.usesAllowanceOnExport)
        model.markExported()
        #expect(model.allowance.remainingToday == 1)
    }

    /// 時刻を「そのまま」にすると、元の時刻（2:47）が残る
    @Test
    func keepsOriginalTime() async throws {
        let sample = try await sample()
        let bandHeight = try #require(sample.screenshot.bandHeight)

        sample.model.setTimeChoice(.keep)
        await sample.model.waitForRender()

        #expect(sample.model.spec.time == .keep)
        // 左半分（時刻のある側）は、元の画像と同じ
        let before = try Bitmap(cgImage: sample.screenshot.before)
        let after = try Bitmap(cgImage: sample.model.image)
        #expect((0..<bandHeight).allSatisfy { y in (0..<(after.width / 2)).allSatisfy { after[$0, y] == before[$0, y] } })
    }

    /// 時刻を選び直すまでは、地域によらず「整える」と同じ `9:41` で描く。
    /// 英国（`09:41` と書く地域）でも、電池だけを変えたときに、時刻の表記が変わらない
    @Test
    func keepsStandardTimeTextUntilTimeIsPicked() async throws {
        let sample = try await sample(locale: "en_GB")
        let model = sample.model

        #expect(model.timeText == "9:41")
        #expect(model.spec == .standard)

        model.setBatteryPercent(60)
        await model.waitForRender()
        #expect(model.spec.time == .set("9:41"))

        // 時刻を選び直したら、その地域の書き方になる
        model.setTime(hour: 14, minute: 8)
        #expect(model.timeText == "14:08")
        model.setTime(hour: 9, minute: 41)
        #expect(model.timeText == "09:41")
        #expect(model.spec.time == .set("09:41"))
    }

    /// 選び直した時刻は、地域の書き方の文字列で描く
    @Test
    func usesLocaleForTimeText() async throws {
        let sample = try await sample(locale: "en_US")

        sample.model.setTime(hour: 14, minute: 8)

        #expect(sample.model.timeText == "2:08")
        #expect(sample.model.spec.time == .set("2:08"))
        // 範囲の外の値は、範囲に収める
        sample.model.setTime(hour: 30, minute: -4)
        #expect(sample.model.hour == 23 && sample.model.minute == 0)
    }

    /// 値は、選べる範囲に収める
    @Test
    func clampsValues() async throws {
        let model = try await sample().model

        model.setBatteryPercent(0)
        #expect(model.batteryPercent == 1)
        model.setBatteryPercent(500)
        #expect(model.batteryPercent == 100)
        model.setCellularBars(9)
        #expect(model.cellularBars == 4)
        model.setCellularBars(-1)
        #expect(model.cellularBars == 0)
        model.setWiFiBars(7)
        #expect(model.wifiBars == 3)
        model.setWiFiBars(nil)
        #expect(model.wifiBars == nil)
    }
}

/// 編集の結果に、「遊ぶ」の状態が付く
@MainActor
struct EditSessionPlayTests {
    @Test
    func createsPlayModelWhenStatusBarIsHidden() async {
        let allowance = PlayAllowance(store: InMemoryPlayUsageStore())
        let session = EditSession(source: { try SampleScreenshot.pngData() }, allowance: allowance)

        await session.start()

        #expect(session.play?.allowance === allowance)
    }

    @Test
    func hasNoPlayModelWhenStatusBarIsNotHidden() async {
        let session = EditSession(
            source: { try SampleScreenshot.resavedPNGData() }, allowance: PlayAllowance(store: InMemoryPlayUsageStore())
        )

        await session.start()

        guard case .ready = session.phase else {
            Issue.record("ready になっていない: \(session.phase)")
            return
        }
        #expect(session.play == nil)
    }
}
