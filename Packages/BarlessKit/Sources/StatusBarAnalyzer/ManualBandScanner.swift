import ImageIOKit

/// 手動調整で、利用者が合わせた帯から拾ったもの
public struct ManualBandScan: Sendable, Equatable {
    /// 消す画素。インクを、縁のにじみまで覆うように 1pt 広げたもの
    public let eraseMask: PixelMask
    public let background: BackgroundKind
    /// 消した跡が残りそうか（背景が写真・模様、または背景の輪郭が帯を横切っている）
    public let mayLeaveTraces: Bool
}

/// 配置（機種）が分からない画像で、利用者が合わせた帯（画像の上端から `bandHeight` 行）からインクを拾う。
///
/// 自動の判定と同じ方法（上下の基準の行を直線で補間した色との差）を使う。違いは次の 2 つ。
/// - 基準の行は、帯のいちばん上の行といちばん下の行。帯のすぐ下の行を使わないのは、
///   線をちょうど色の境（ステータスバーの下で背景の色が変わるアプリ）に合わせたときに、境の下の色を背景と見込まないため
/// - 文字・アイコンの位置が分からないので、背景の輪郭を拾ったインクも消す。ステータスバーを確実に隠すほうを優先する
public struct ManualBandScanner: Sendable {
    /// 背景の輪郭を拾ったインクがこの面積（pt²）以上あれば、跡が残るとみなす（自動の判定と同じ値）
    static let visibleStructureAreaPt = 4

    /// 1pt が何 px かの見込み。縁を覆う幅などに使う
    public let scale: Int

    public init(scale: Int) {
        self.scale = max(1, scale)
    }

    /// 帯が低すぎる・画像に入りきらないときは `nil`
    public func scan(_ bitmap: Bitmap, bandHeight: Int, tone: InkTone = .any) -> ManualBandScan? {
        guard bandHeight >= 3, bandHeight <= bitmap.height else { return nil }
        let detector = InkDetector(scale: scale, topRow: 0, bottomRow: bandHeight - 1)
        let scan = detector.scan(bitmap, keeping: tone)
        let structure = scan.structure.count
        return ManualBandScan(
            eraseMask: scan.mask.dilated(by: scale),
            background: scan.background,
            mayLeaveTraces: scan.background == .complex || structure >= Self.visibleStructureAreaPt * scale * scale
        )
    }
}
