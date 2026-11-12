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

    /// 文字・アイコンの範囲を、この幅（pt）だけ広げて見る（実測とのずれ・縁のにじみの分）
    static let elementMarginPt = 2
    /// 文字・アイコンの後ろに、背景の輪郭がこの面積（pt²）以上あれば、跡が残るとみなす
    static let visibleStructureAreaPt = 4

    /// 消去に使うマスク。インクの画素を、縁のにじみまで覆うように 1pt 広げたもの。
    ///
    /// 背景の輪郭を拾ったインクは、文字・アイコンの範囲の外では消さない（`backgroundInk()`）。
    /// 消すと、何も無かったところの輪郭がぼやけるため
    public func eraseMask() -> PixelMask? {
        guard let scan, let layout = decision.layout else { return nil }
        var ink = scan.mask
        for pixel in backgroundInk() {
            ink[pixel.x, pixel.y] = false
        }
        return ink.dilated(by: layout.scale)
    }

    /// 背景の輪郭（建物の縁・壁紙の模様など）が、文字・アイコンの後ろを通っているか。
    /// 通っていると、消した後に輪郭がぼやけて残る
    public var hasStructureBehindInk: Bool {
        guard let layout = decision.layout else { return false }
        return structureBehindElements() >= Self.visibleStructureAreaPt * layout.scale * layout.scale
    }

    /// 背景で埋めると跡が残りそうか（写真・模様の背景、または文字・アイコンの後ろを輪郭が通っている）
    public var mayLeaveTraces: Bool {
        background == .complex || hasStructureBehindInk
    }

    /// 文字・アイコンの範囲の中にある、背景の輪郭の画素数。
    /// 輪郭が文字・アイコンとつながっているときは、その文字・アイコン自体の画素も数に入る
    func structureBehindElements() -> Int {
        guard let scan, case let .resolved(match, _) = decision else { return 0 }
        let elements = elementRects(of: match)
        let structure = scan.structure
        var count = 0
        for y in structure.originY..<(structure.originY + structure.height) {
            for x in structure.originX..<(structure.originX + structure.width) where structure[x, y] {
                if elements.contains(where: { $0.contains(x: x, y: y) }) { count += 1 }
            }
        }
        return count
    }

    /// 背景を拾ったとみなして、消さないインク。
    ///
    /// 背景の輪郭を含むかたまり（`InkScan.blobs` のうち `structure` と重なるもの）の中で、文字・アイコンの範囲の外にある画素。
    /// かたまりごと見るのは、輪郭のまわりの模様（帯の端までは届かない細かいインク）も一緒に外すため
    func backgroundInk() -> [(x: Int, y: Int)] {
        guard let scan, case let .resolved(match, _) = decision else { return [] }
        let elements = elementRects(of: match)
        var result: [(x: Int, y: Int)] = []
        for blob in scan.blobs where Self.contains(scan.structure, in: blob) {
            for y in blob.y..<blob.maxY {
                for x in blob.x..<blob.maxX where scan.mask[x, y] {
                    if !elements.contains(where: { $0.contains(x: x, y: y) }) { result.append((x, y)) }
                }
            }
        }
        return result
    }

    private static func contains(_ structure: PixelMask, in rect: PixelRect) -> Bool {
        for y in rect.y..<rect.maxY {
            for x in rect.x..<rect.maxX where structure[x, y] { return true }
        }
        return false
    }

    /// 配置から見て、文字とアイコンがある範囲（`elementMarginPt` だけ広げてある）
    private func elementRects(of match: LayoutMatch) -> [PixelRect] {
        let layout = match.layout
        // 時刻は文字列で幅が変わる。読めていれば、その文字列を描いたときの範囲を使う
        let time = timeText.map { TimeTypography(layout: layout).inkRect(for: $0) } ?? match.timeBlob
        let margin = Self.elementMarginPt * layout.scale
        return [time, layout.cellular, layout.wifi, layout.battery, layout.carrier]
            .compactMap { $0 }
            .map { $0.insetBy(dx: -margin, dy: -margin) }
    }
}

/// スクリーンショットから、機種グループ・iOS の世代・インクの位置・背景の種類を調べる（仕様書 §5-2）。
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
        let inks = candidates.flatMap { $0.timeSamples.map(\.ink) }
        guard let scale = candidates.first?.scale, let first = inks.first else { throw BitmapError.emptyImage }
        let bounds = inks.dropFirst().reduce(first) { $0.union($1) }
        // 「23:58」のように桁が多いと左右に広がるので、横は広めに取る
        let region = bounds.insetBy(dx: -Self.timeMarginXPt * scale, dy: -Self.timeMarginYPt * scale)
        let visible = region.intersection(PixelRect(x: 0, y: 0, width: strip.width, height: strip.height))
        guard !visible.isEmpty else { throw BitmapError.emptyImage }
        let crop = strip.cropped(x: visible.x, y: visible.y, width: visible.width, height: visible.height)
        return try crop.enlarged(by: Self.timeMagnification).makeCGImage()
    }

    /// 時刻の文字列が分かっているとき（または文字認識を使わないとき）の解析。同期で呼べる
    public static func analyze(strip: Bitmap, pixelHeight: Int, timeText: String?, catalog: DeviceCatalog) -> StatusBarAnalysis {
        let resolved = LayoutResolver(catalog: catalog).resolve(strip: strip, pixelHeight: pixelHeight, timeText: timeText)
        return StatusBarAnalysis(decision: resolved.decision, timeText: timeText, scan: resolved.scan, candidates: resolved.matches)
    }
}
