import CoreGraphics
import DeviceCatalog
import ImageIOKit
import StatusBarRenderer

/// スクリーンショット 1 枚の解析結果
public struct StatusBarAnalysis: Sendable, Equatable {
    /// 機種グループと iOS の世代の判定
    public let decision: LayoutDecision
    /// 文字認識で読んだ時刻（読めなかったら `nil`）
    public let timeText: String?
    /// 帯から拾ったインク（カタログに無い大きさのときは `nil`）
    public let scan: InkScan?
    /// 大きさが一致した候補すべて（時刻のずれが小さい順）。手動調整で候補を出すときに使う
    public let candidates: [LayoutMatch]

    /// 文字とアイコンの色
    public var appearance: ContentAppearance? {
        scan.map { $0.inkIsDark ? .darkContent : .lightContent }
    }

    public var background: BackgroundKind? { scan?.background }

    /// 消去に使うマスク。インクの画素を、縁のにじみまで覆うように 1pt 広げたもの
    public func eraseMask() -> PixelMask? {
        guard let scan, let layout = decision.layout else { return nil }
        return scan.mask.dilated(by: layout.scale)
    }
}

/// スクリーンショットから、機種グループ・iOS の世代・インクの位置・背景の種類を調べる（docs/spec.md §5-2）。
///
/// 流れ: 大きさ（px）でカタログから候補を引く → 帯の中だけ文字認識で時刻を読む → 時刻の位置と大きさで候補を 1 つに決める。
public actor StatusBarAnalyzer {
    /// 解析に使う上端の高さ（px）。どの機種でも、ステータスバーとそのすぐ下の背景が入る
    static let stripHeight = 240
    /// 文字認識に渡す範囲を、実測の時刻の矩形からどれだけ広げるか（pt）と、拡大の倍率
    static let timeMarginXPt = 24
    static let timeMarginYPt = 8
    static let timeMagnification = 3

    private let catalog: DeviceCatalog
    private let recognizer: any TimeTextRecognizing

    public init(catalog: DeviceCatalog, recognizer: any TimeTextRecognizing = VisionTimeTextRecognizer()) {
        self.catalog = catalog
        self.recognizer = recognizer
    }

    /// スクリーンショット全体を渡す
    public func analyze(_ image: CGImage) async throws -> StatusBarAnalysis {
        let height = min(image.height, Self.stripHeight)
        guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)) else {
            throw BitmapError.emptyImage
        }
        return try await analyze(strip: Bitmap(cgImage: top), pixelHeight: image.height)
    }

    /// 上端だけを切り出した画像と、元の高さを渡す
    public func analyze(strip: Bitmap, pixelHeight: Int) async -> StatusBarAnalysis {
        let candidates = catalog.candidates(pixelWidth: strip.width, pixelHeight: pixelHeight)
        guard !candidates.isEmpty else {
            return Self.analyze(strip: strip, pixelHeight: pixelHeight, timeText: nil, catalog: catalog)
        }
        // 文字認識に失敗しても、時刻の高さと中心だけで判定を続ける
        var times: [String] = []
        if let image = try? Self.timeImage(strip: strip, candidates: candidates) {
            times = (try? await recognizer.recognizeTimes(in: image)) ?? []
        }
        return Self.analyze(strip: strip, pixelHeight: pixelHeight, timeText: times.first, catalog: catalog)
    }

    /// 文字認識に渡す画像。時刻がありそうな範囲だけを切り出して拡大する。
    /// 帯全体をそのまま渡すと、文字が小さく（高さ 12pt ほど）まれに見落とすため
    static func timeImage(strip: Bitmap, candidates: [StatusBarLayout]) throws -> CGImage {
        let scale = candidates[0].scale
        let inks = candidates.flatMap { $0.timeSamples.map(\.ink) }
        let bounds = inks.dropFirst().reduce(inks[0]) { $0.union($1) }
        // 「23:58」のように桁が多いと左右に広がるので、横は広めに取る
        let region = bounds.insetBy(dx: -Self.timeMarginXPt * scale, dy: -Self.timeMarginYPt * scale)
        let crop = strip.cropped(x: region.x, y: region.y, width: region.width, height: region.height)
        return try crop.enlarged(by: Self.timeMagnification).makeCGImage()
    }

    /// 時刻の文字列が分かっているとき（または文字認識を使わないとき）の解析。同期で呼べる
    public static func analyze(strip: Bitmap, pixelHeight: Int, timeText: String?, catalog: DeviceCatalog) -> StatusBarAnalysis {
        let resolved = LayoutResolver(catalog: catalog).resolve(strip: strip, pixelHeight: pixelHeight, timeText: timeText)
        return StatusBarAnalysis(decision: resolved.decision, timeText: timeText, scan: resolved.scan, candidates: resolved.matches)
    }
}
