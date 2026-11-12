import CoreGraphics
import Foundation
import Observation
import StatusBarEditor
import StatusBarRenderer

/// 「遊ぶ」の状態。時刻・電池・電波・Wi-Fi の値を変えるたびに、画像を描き直す
@MainActor
@Observable
final class PlayModel {
    /// 時刻の扱い
    enum TimeChoice: String, CaseIterable, Sendable {
        /// 元の時刻をそのまま残す
        case keep
        /// 消す
        case hide
        /// 指定した時刻に描き直す
        case set
    }

    static let batteryRange = 1...100
    static let cellularRange = 0...4
    static let wifiRange = 0...3

    private(set) var timeChoice = TimeChoice.set
    /// 描き直す時刻（時は 0〜23）
    private(set) var hour = 9
    private(set) var minute = 41
    /// 電池の残量（%）
    private(set) var batteryPercent = 100
    /// 電波の本数（0〜4）
    private(set) var cellularBars = 4
    /// Wi-Fi の本数（0〜3）。`nil` はオフ（消す）
    private(set) var wifiBars: Int? = 3
    /// いまの中身で描いた画像
    private(set) var image: CGImage

    private let composer: StatusBarComposer
    private let locale: Locale
    private let renderer = PlayRenderer()
    /// まだ描いていない、いちばん新しい中身
    private var pendingSpec: PlaySpec?
    /// 描いている処理。描き終えると `nil` に戻る
    private var renderTask: Task<Void, Never>?

    /// - Parameters:
    ///   - initialImage: 最初の中身（「整える」と同じ）で描いた画像。「整える」の結果をそのまま使える
    ///   - locale: 時刻の書き方（12 時間制か 24 時間制か）を決める地域
    init(composer: StatusBarComposer, initialImage: CGImage, locale: Locale = .current) {
        self.composer = composer
        self.image = initialImage
        self.locale = locale
    }

    /// 描き直す時刻の文字列（`9:41`）。12 時間制の地域では午前・午後を付けない（ステータスバーの表示と同じ）
    var timeText: String {
        PlayTime.text(hour: hour, minute: minute, locale: locale)
    }

    /// いまの中身
    var spec: PlaySpec {
        let time: PlaySpec.Time = switch timeChoice {
        case .keep: .keep
        case .hide: .hide
        case .set: .set(timeText)
        }
        return PlaySpec(
            time: time,
            cellularBars: cellularBars,
            wifiBars: wifiBars,
            battery: BatterySpec(level: Double(batteryPercent) / 100)
        )
    }

    func setTimeChoice(_ choice: TimeChoice) {
        guard choice != timeChoice else { return }
        timeChoice = choice
        render()
    }

    func setTime(hour: Int, minute: Int) {
        let hour = min(max(hour, 0), 23)
        let minute = min(max(minute, 0), 59)
        guard hour != self.hour || minute != self.minute else { return }
        self.hour = hour
        self.minute = minute
        render()
    }

    func setBatteryPercent(_ percent: Int) {
        let percent = min(max(percent, Self.batteryRange.lowerBound), Self.batteryRange.upperBound)
        guard percent != batteryPercent else { return }
        batteryPercent = percent
        render()
    }

    func setCellularBars(_ bars: Int) {
        let bars = min(max(bars, Self.cellularRange.lowerBound), Self.cellularRange.upperBound)
        guard bars != cellularBars else { return }
        cellularBars = bars
        render()
    }

    /// - Parameter bars: `nil` はオフ
    func setWiFiBars(_ bars: Int?) {
        let bars = bars.map { min(max($0, Self.wifiRange.lowerBound), Self.wifiRange.upperBound) }
        guard bars != wifiBars else { return }
        wifiBars = bars
        render()
    }

    /// 画像が、いまの中身に追いつくまで待つ（書き出しの前と、テストで使う）
    func waitForRender() async {
        await renderTask?.value
    }

    /// 描き直す。描いている間に中身が変わったら、いちばん新しいものだけを続けて描く
    private func render() {
        pendingSpec = spec
        guard renderTask == nil else { return }
        renderTask = Task {
            while let next = pendingSpec {
                pendingSpec = nil
                if let rendered = try? await renderer.render(next, with: composer) {
                    image = rendered
                }
            }
            renderTask = nil
        }
    }
}

/// 描き直しの処理。画像の全体を作るので、メインスレッドの外で動かす
nonisolated struct PlayRenderer: Sendable {
    @concurrent
    func render(_ spec: PlaySpec, with composer: StatusBarComposer) async throws -> CGImage {
        try composer.render(spec)
    }
}

/// 時刻の文字列
nonisolated enum PlayTime {
    /// その地域の書き方での時刻。午前・午後は付けない（ステータスバーの表示と同じ）。
    /// 米国は `2:08`、日本は `14:08`、英国は `09:41` のように、12 時間制か 24 時間制かと、時の桁数が地域で変わる
    static func text(hour: Int, minute: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.dateFormat = pattern(for: locale)
        guard let date = calendar.date(from: components) else { return "\(hour):\(minute)" }
        return formatter.string(from: date)
    }

    /// その地域の「時:分」の書式から、午前・午後の部分を除いたもの（`h:mm` `H:mm` `HH:mm` など）
    static func pattern(for locale: Locale) -> String {
        let template = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "H:mm"
        // 午前・午後を表す記号（a・b・B）と、その前後の空白を除く
        let withoutPeriod = template.filter { !"abB".contains($0) }
        return withoutPeriod.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{202F}\u{00A0}")))
    }
}
