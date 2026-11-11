import DeviceCatalog
import ImageIOKit
import StatusBarRenderer

/// 候補の配置 1 つについての、判定の材料
public struct LayoutMatch: Sendable, Equatable {
    public let layout: StatusBarLayout
    /// 時刻の位置と大きさのずれ（pt）。その配置で同じ時刻を描いたときの見込みと、画像から測った矩形との、4 辺の差の合計
    public let timeError: Double
    /// 時刻とみなしたインクのかたまり（px）
    public let timeBlob: PixelRect?
}

/// 判定に使った手がかり
public enum LayoutEvidence: String, Sendable, Equatable {
    /// 大きさだけで 1 つに決まった
    case sizeOnly
    /// 時刻の位置と大きさで決まった
    case time
    /// 時刻では差が付かず、電池の形（枠があるか）で iOS の世代を決めた
    case batteryStyle
}

/// 機種グループと iOS の世代の判定結果
public enum LayoutDecision: Sendable, Equatable {
    case resolved(LayoutMatch, evidence: LayoutEvidence)
    /// 候補を 1 つに絞れなかった（手動調整へ）。`matches` はずれの小さい順
    case ambiguous(matches: [LayoutMatch])
    /// 大きさは分かるが、自動判定の対象にしていない（iPhone Duo など）
    case unsupported(UnsupportedScreen)
    /// カタログに無い大きさ（SNS で再圧縮された画像など）
    case unknownSize

    public var layout: StatusBarLayout? {
        if case let .resolved(match, _) = self { return match.layout }
        return nil
    }
}

/// 「大きさで候補を絞る → 時刻の位置と大きさで決める」判定（仕様書 §5-2）。
///
/// 時刻は文字列によって幅が変わるので、候補ごとに「その配置で同じ文字列を描いたらどこにインクが載るか」を
/// 計算し、画像から測った矩形と比べる（文字列が分からないときは、高さと中心だけで比べる）。
struct LayoutResolver {
    /// ずれがこれ以下なら、その配置として受け入れる（pt。4 辺の差の合計）
    static let acceptableTimeError = 2.5
    /// 1 位と 2 位のずれの差がこれより小さいと、時刻だけでは決めない（pt）
    static let decisiveMargin = 1.0

    let catalog: DeviceCatalog

    /// - Parameters:
    ///   - strip: スクリーンショットの上端（ステータスバーを含む）
    ///   - pixelHeight: 切り出す前のスクリーンショットの高さ
    ///   - timeText: 文字認識で読んだ時刻。読めなかったら `nil`
    func resolve(strip: Bitmap, pixelHeight: Int, timeText: String?) -> Resolution {
        let candidates = catalog.candidates(pixelWidth: strip.width, pixelHeight: pixelHeight)
        guard let first = candidates.first else {
            if let unsupported = catalog.unsupportedScreen(pixelWidth: strip.width, pixelHeight: pixelHeight) {
                return Resolution(decision: .unsupported(unsupported), scan: nil, matches: [])
            }
            return Resolution(decision: .unknownSize, scan: nil, matches: [])
        }
        let inkTop = candidates.map(\.inkTop).min() ?? first.inkTop
        let inkBottom = candidates.map(\.inkBottom).max() ?? first.inkBottom
        let detector = InkDetector(scale: first.scale, inkTop: inkTop, inkBottom: inkBottom, imageHeight: strip.height)
        let scan = detector.scan(strip)
        let matches = candidates
            .map { match($0, blobs: scan.blobs, timeText: timeText) }
            .sorted { $0.timeError < $1.timeError }
        let decision = candidates.count == 1
            ? LayoutDecision.resolved(matches[0], evidence: .sizeOnly)
            : decide(matches, strip: strip, detector: detector, scan: scan)
        return Resolution(decision: decision, scan: scan, matches: matches)
    }

    struct Resolution {
        let decision: LayoutDecision
        let scan: InkScan?
        /// 大きさが一致した候補すべて。時刻のずれが小さい順
        let matches: [LayoutMatch]
    }

    private func decide(_ matches: [LayoutMatch], strip: Bitmap, detector: InkDetector, scan: InkScan) -> LayoutDecision {
        let best = matches[0]
        guard best.timeError <= Self.acceptableTimeError else { return .ambiguous(matches: matches) }
        let contenders = matches.filter { $0.timeError - best.timeError < Self.decisiveMargin }
        if contenders.count == 1 { return .resolved(best, evidence: .time) }
        // 時刻の位置と大きさが同じ配置が残った（iPhone 11 系・SE の iOS 18〜26 と 27）。電池の形で世代を決める
        let probe = BatteryStyleProbe(detector: detector)
        if let generation = probe.generation(in: strip, scan: scan, near: best.layout.battery) {
            let narrowed = contenders.filter { $0.layout.generation == generation }
            if narrowed.count == 1 { return .resolved(narrowed[0], evidence: .batteryStyle) }
        }
        return .ambiguous(matches: matches)
    }

    /// 候補の配置と、画像から測ったインクを比べる
    func match(_ layout: StatusBarLayout, blobs: [PixelRect], timeText: String?) -> LayoutMatch {
        let typography = TimeTypography(layout: layout)
        let scale = Double(layout.scale)
        guard let text = timeText else {
            return matchWithoutText(layout, typography: typography, blobs: blobs)
        }
        let expected = typography.inkRect(for: text)
        // 見込みの矩形といちばん重なるかたまりを時刻とみなす
        let overlapping = blobs
            .map { (blob: $0, overlap: $0.intersection(expected)) }
            .filter { !$0.overlap.isEmpty }
            .max { $0.overlap.width * $0.overlap.height < $1.overlap.width * $1.overlap.height }
        guard let blob = overlapping?.blob else {
            return LayoutMatch(layout: layout, timeError: .infinity, timeBlob: nil)
        }
        let error = abs(blob.x - expected.x) + abs(blob.y - expected.y)
            + abs(blob.maxX - expected.maxX) + abs(blob.maxY - expected.maxY)
        return LayoutMatch(layout: layout, timeError: Double(error) / scale, timeBlob: blob)
    }

    /// 文字列が分からないとき: 高さ（上端と下端）と、中央ぞろえの中心だけで比べる
    private func matchWithoutText(_ layout: StatusBarLayout, typography: TimeTypography, blobs: [PixelRect]) -> LayoutMatch {
        let scale = Double(layout.scale)
        // 数字はどれもほぼ同じ高さなので、高さは「0」で代表させる
        let expected = typography.inkRect(for: "0")
        let centerX = Double(typography.centerX)
        guard let blob = blobs.min(by: { abs($0.midX - centerX) < abs($1.midX - centerX) }),
              Double(blob.x) <= centerX, centerX <= Double(blob.maxX) else {
            return LayoutMatch(layout: layout, timeError: .infinity, timeBlob: nil)
        }
        // インクの中心は、文字の左右の余白の違いで送り幅の中心から 1pt ほどずれることがある
        let centerError = max(0, abs(blob.midX - centerX) - scale)
        let error = Double(abs(blob.y - expected.y) + abs(blob.maxY - expected.maxY)) + 2 * centerError
        return LayoutMatch(layout: layout, timeError: error / scale, timeBlob: blob)
    }
}

/// 電池の形から iOS の世代を見分ける。
///
/// iOS 18〜26 の電池は「枠・すき間・中身」の順に並ぶので、左端から中へ進むと、枠のすぐ内側で背景の色に戻る。
/// iOS 27 の電池は枠のないカプセル形で、左端からずっと塗られている。
struct BatteryStyleProbe {
    /// 背景との差が、それまでの最大のこの割合を下回ったら「すき間」とみなす。
    /// JPEG で再圧縮された画像ではすき間が背景の色に戻りきらないので、絶対値ではなく比で見る
    static let gapRatio = 0.4

    let detector: InkDetector

    /// - Parameter expected: 候補の配置での電池の位置（px）。この近くのインクのかたまりを電池とみなす
    func generation(in bitmap: Bitmap, scan: InkScan, near expected: PixelRect) -> OSGeneration? {
        let tolerance = 2 * detector.scale
        guard let blob = scan.blobs.first(where: { $0.maxEdgeDistance(to: expected) <= tolerance }) else { return nil }
        // 中央の 3 行で見て、多いほうを採る
        let middle = blob.y + blob.height / 2
        let votes = (middle - 1...middle + 1).compactMap { hasGap(in: bitmap, blob: blob, y: $0) }
        guard !votes.isEmpty else { return nil }
        return votes.filter { $0 }.count * 2 > votes.count ? .iOS18to26 : .iOS27
    }

    /// 左端から、枠（1pt）とすき間（1pt）の先まで進み、塗りが途切れるかを見る。インクが無ければ `nil`
    private func hasGap(in bitmap: Bitmap, blob: PixelRect, y: Int) -> Bool? {
        var peak = 0
        for x in blob.x..<min(blob.maxX, blob.x + 3 * detector.scale) {
            let difference = bitmap[x, y].distance(to: detector.expectedColor(bitmap, x: x, y: y))
            if peak > InkDetector.inkThreshold, Double(difference) < Double(peak) * Self.gapRatio { return true }
            peak = max(peak, difference)
        }
        return peak > InkDetector.inkThreshold ? false : nil
    }
}
