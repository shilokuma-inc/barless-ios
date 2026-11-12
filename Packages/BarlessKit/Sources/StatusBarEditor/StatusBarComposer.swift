import CoreGraphics
import DeviceCatalog
import ImageIOKit
import InpaintEngine
import StatusBarAnalyzer
import StatusBarRenderer

/// 「遊ぶ」で描くステータスバーの中身
public struct PlaySpec: Sendable, Equatable {
    /// 時刻の扱い
    public enum Time: Sendable, Equatable {
        /// 元の時刻を、そのまま残す
        case keep
        /// 消す
        case hide
        /// この文字列に描き直す（例: `9:41`）
        case set(String)
    }

    public var time: Time
    /// 電波の本数（0〜4）。`nil` なら消す
    public var cellularBars: Int?
    /// Wi-Fi の本数（0〜3）。`nil` なら消す（オフ）
    public var wifiBars: Int?
    /// 電池。`nil` なら消す
    public var battery: BatterySpec?

    public init(time: Time, cellularBars: Int?, wifiBars: Int?, battery: BatterySpec?) {
        self.time = time
        self.cellularBars = cellularBars
        self.wifiBars = wifiBars
        self.battery = battery
    }

    /// 「整える」と同じ中身（9:41・電波 4 本・Wi-Fi 最大・電池満タン）
    public static let standard = PlaySpec(StatusBarSpec.tidy)

    /// 時刻があれば描き直し、無ければ消す中身にする
    public init(_ spec: StatusBarSpec) {
        self.init(
            time: spec.time.map(Time.set) ?? .hide, cellularBars: spec.cellularBars, wifiBars: spec.wifiBars, battery: spec.battery
        )
    }
}

/// 解析した 1 枚のステータスバーを、中身を変えて何度でも描き直す。
///
/// 消した後の画像を持っておき、描き直すたびに、その上に自作のベクターと時刻を載せる。
/// 解析と消去はやり直さないので、値を変えるたびにすぐ結果を出せる。書き換えるのはステータスバーの帯の中だけ
public struct StatusBarComposer: Sendable {
    public let layout: StatusBarLayout
    public let appearance: ContentAppearance
    /// 「整える」と同じ合わせ方（ホームボタンの機種では、キャリア名を残して、Wi-Fi をその右に置く）
    let plan: TidyPlan
    /// ステータスバーを消した画像の全体
    let erased: Bitmap
    /// 上端の切り出し。すべて消したもの（キャリア名は残す）
    let clearedStrip: Bitmap
    /// 上端の切り出し。時刻だけを残して消したもの
    let timeKeptStrip: Bitmap

    /// - Parameters:
    ///   - source: 元の画像
    ///   - erased: 「隠す」の結果（`source` の文字とアイコンを消したもの）
    init(
        source: Bitmap,
        erased: Bitmap,
        analysis: StatusBarAnalysis,
        layout: StatusBarLayout,
        appearance: ContentAppearance,
        plan: TidyPlan,
        inpainter: any Inpainter
    ) async throws {
        self.layout = layout
        self.appearance = appearance
        self.plan = plan
        self.erased = erased
        // 消去は、帯の中の画素だけを読み書きする。上端だけを切り出して消しても、全体を消したときと同じ結果になる
        let strip = source.cropped(x: 0, y: 0, width: source.width, height: Self.stripHeight(of: analysis, in: source))
        if let mask = analysis.eraseMask(keeping: plan.kept) {
            clearedStrip = try await inpainter.inpaint(strip, mask: mask)
        } else {
            clearedStrip = strip
        }
        let kept = plan.kept + [analysis.timeRect].compactMap { $0 }
        if let mask = analysis.eraseMask(keeping: kept) {
            timeKeptStrip = try await inpainter.inpaint(strip, mask: mask)
        } else {
            timeKeptStrip = strip
        }
    }

    /// 上端の切り出しの高さ。消去で読み書きする行（インクの上下 3pt まで）が入る高さにする
    private static func stripHeight(of analysis: StatusBarAnalysis, in source: Bitmap) -> Int {
        guard let mask = analysis.scan?.mask, let scale = analysis.decision.layout?.scale else { return source.height }
        return min(source.height, mask.originY + mask.height + 2 * scale)
    }

    /// `spec` の中身に描き直した画像（全体）を作る
    public func render(_ spec: PlaySpec) throws -> CGImage {
        try renderBitmap(spec).makeCGImage()
    }

    /// `spec` の中身に描き直した画像（全体）。テストで画素を比べるのに使う
    public func renderBitmap(_ spec: PlaySpec) throws -> Bitmap {
        var content = StatusBarSpec(cellularBars: spec.cellularBars, wifiBars: spec.wifiBars, battery: spec.battery)
        if case let .set(time) = spec.time { content.time = time }
        // キャリア名が長くて Wi-Fi の入る場所が無い画像では、Wi-Fi は描かない
        if !plan.drawsWiFi { content.wifiBars = nil }
        var bitmap = erased
        bitmap.replaceTopRows(with: spec.time == .keep ? timeKeptStrip : clearedStrip)
        try StatusBarRenderer().render(content, layout: layout, appearance: appearance, into: &bitmap, wifiShiftX: plan.wifiShiftX)
        return bitmap
    }
}
