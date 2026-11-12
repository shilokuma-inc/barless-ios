import DeviceCatalog
import ImageIOKit

/// 背景の種類（仕様書 §5-2）
public enum BackgroundKind: String, Sendable, Equatable {
    /// 単色
    case solid
    /// なめらかに変わるグラデーション
    case gradient
    /// 写真・模様など。背景で埋めると跡が残りやすい
    case complex
}

/// 拾うインクの明るさ。文字の色が分かっているときに、背景の模様を拾わないために使う
public enum InkTone: String, Sendable, CaseIterable {
    /// 背景より明るいものも暗いものも拾う
    case any
    /// 背景より明るいものだけを拾う（白い文字）
    case light
    /// 背景より暗いものだけを拾う（黒い文字）
    case dark

    func keeps(isDarker: Bool) -> Bool {
        switch self {
        case .any: true
        case .light: !isDarker
        case .dark: isDarker
        }
    }
}

/// ステータスバーの帯から拾った「インク」（文字・アイコン）
public struct InkScan: Sendable, Equatable {
    /// インクの画素。帯の範囲だけを覆う
    public let mask: PixelMask
    /// インクのうち、帯を横切る背景の輪郭とみなしたもの（建物の縁・壁紙の模様など）。`mask` の一部
    public let structure: PixelMask
    /// 背景の基準にする行（帯のすぐ上）で、横に色が大きく変わる列（px。左から）。
    /// まっすぐ縦に通る輪郭は、上下の基準の行で色が同じなのでインクとして拾えない。その代わりに、ここで見つける
    public let edgesAbove: [Int]
    /// 同じく、帯のすぐ下の行で、横に色が大きく変わる列
    public let edgesBelow: [Int]
    /// 横に 3pt 以上あいたところで分けた、インクのかたまり（左から）
    public let blobs: [PixelRect]
    public let background: BackgroundKind
    /// 背景より暗いインクが多ければ `true`（黒い文字 = 明るい背景）
    public let inkIsDark: Bool
}

/// 帯の上と下の行を背景とみなし、その間を直線で補間した色との差でインクを拾う。
///
/// 単色でなくても、縦方向に直線的に変わる背景（グラデーション、縦の境界線）ならインクだけが残る。
/// 斜めの輪郭や模様があると背景までインクとして拾うので、そのときは `complex` と判定する。
struct InkDetector {
    /// インクとみなす色の差（3 チャンネルの差の合計。実測スクリプト analyze.py と同じ）
    static let inkThreshold = 60
    /// これ以上の差があれば「背景そのままではない」とみなす（縁のにじみを数える）
    static let noiseThreshold = 12
    /// 要素を分けるすき間（pt）。要素の中のすき間は 2pt 以下、要素どうしは 4.5pt 以上（docs/device-table.md）
    static let blobGapPt = 3
    /// 画面の左右の端からこの幅（pt）は見ない。Simulator や Mac で保存した画像は四隅が黒く欠けることがある
    static let sideMarginPt = 4
    /// 帯の上端・下端からこの幅（pt）にインクがあれば、帯の外から続く背景の輪郭とみなす。
    /// 文字とアイコンは、帯の端（基準の行）から 3pt 離れている
    static let structureEdgePt = 1
    /// 基準の行で、1pt 離れた画素の色の差（3 チャンネルの合計）がこれ以上なら、輪郭とみなす。
    /// 縦の輪郭が文字・アイコンの後ろを通るとき、左右の差がこのあたりから、消した跡が目に見える（docs/verification.md §3-5）
    static let edgeContrast = 200

    let scale: Int
    /// 背景の基準にする行（帯のすぐ上とすぐ下）
    let topRow: Int
    let bottomRow: Int

    /// - Parameters:
    ///   - inkTop: 候補の配置のうち、いちばん上のインクの位置（px）
    ///   - inkBottom: いちばん下のインクの位置（px。含まない）
    init(scale: Int, inkTop: Int, inkBottom: Int, imageHeight: Int) {
        self.scale = scale
        self.topRow = max(0, inkTop - 3 * scale)
        self.bottomRow = min(imageHeight - 1, inkBottom + 3 * scale)
    }

    /// 基準の行をじかに決める。手動調整（配置が分からない画像）で、利用者が合わせた帯の上端と下端を使う
    init(scale: Int, topRow: Int, bottomRow: Int) {
        self.scale = scale
        self.topRow = topRow
        self.bottomRow = bottomRow
    }

    /// - Parameter tone: 拾うインクの明るさ。背景の種類と `inkIsDark` は、明るさで絞る前のインクから決める
    func scan(_ bitmap: Bitmap, keeping tone: InkTone = .any) -> InkScan {
        let margin = Self.sideMarginPt * scale
        // 帯が入りきらない画像（上端の切り出しが短すぎる・幅が狭すぎる）では、何も拾わない
        guard bottomRow > topRow + 1, bitmap.width > 2 * margin else {
            let empty = PixelMask(originX: 0, originY: topRow, width: max(1, bitmap.width), height: 1)
            return InkScan(
                mask: empty, structure: empty, edgesAbove: [], edgesBelow: [], blobs: [], background: .complex, inkIsDark: true
            )
        }
        var mask = PixelMask(originX: 0, originY: topRow + 1, width: bitmap.width, height: max(1, bottomRow - topRow - 1))
        // 明るさで絞るときは、絞る前のインクも別に持つ。背景の種類は、絞る前のかたまりの数で決める
        // （絞った後で数えると、反対の明るさの模様が数に入らず、模様のある背景を単色とみなしてしまう）
        var unfiltered = tone == .any ? nil : mask
        var noisy = 0
        var darker = 0
        var lighter = 0
        for y in (topRow + 1)..<bottomRow {
            for x in margin..<(bitmap.width - margin) {
                let pixel = bitmap[x, y]
                let expected = expectedColor(bitmap, x: x, y: y)
                let difference = pixel.distance(to: expected)
                if difference > Self.inkThreshold {
                    let isDarker = pixel.luma < expected.luma
                    if isDarker { darker += 1 } else { lighter += 1 }
                    if tone.keeps(isDarker: isDarker) { mask[x, y] = true }
                    unfiltered?[x, y] = true
                } else if difference > Self.noiseThreshold {
                    noisy += 1
                }
            }
        }
        let blobs = Self.blobs(in: mask, gap: Self.blobGapPt * scale)
        let allBlobs = unfiltered.map { Self.blobs(in: $0, gap: Self.blobGapPt * scale) } ?? blobs
        let kind = backgroundKind(bitmap, inkCount: darker + lighter, noisyCount: noisy, blobs: allBlobs)
        let structure = Self.structure(in: mask, edge: Self.structureEdgePt * scale)
        return InkScan(
            mask: mask,
            structure: structure,
            edgesAbove: edgeColumns(bitmap, row: topRow),
            edgesBelow: edgeColumns(bitmap, row: bottomRow),
            blobs: blobs,
            background: kind,
            inkIsDark: darker >= lighter
        )
    }

    /// その行で、1pt 右の画素と色が大きく違う列
    private func edgeColumns(_ bitmap: Bitmap, row: Int) -> [Int] {
        let margin = Self.sideMarginPt * scale
        return (margin..<(bitmap.width - margin - scale)).filter { x in
            bitmap[x, row].distance(to: bitmap[x + scale, row]) >= Self.edgeContrast
        }
    }

    /// インクのうち、帯の上端か下端まで届いている、ひと続きのかたまり。
    ///
    /// 背景の見込み（上下の行の直線補間）は、斜めの輪郭があると外れ、輪郭の一部をインクとして拾う。
    /// そういうインクは帯の外の背景から続いているので、帯の端まで届く。文字とアイコンは端まで届かない
    static func structure(in mask: PixelMask, edge: Int) -> PixelMask {
        var result = PixelMask(originX: mask.originX, originY: mask.originY, width: mask.width, height: mask.height)
        let topRows = mask.originY..<min(mask.originY + edge, mask.originY + mask.height)
        let bottomRows = max(mask.originY, mask.originY + mask.height - edge)..<(mask.originY + mask.height)
        var pending: [(x: Int, y: Int)] = []
        for y in Array(topRows) + Array(bottomRows) {
            for x in mask.originX..<(mask.originX + mask.width) where mask[x, y] && !result[x, y] {
                result[x, y] = true
                pending.append((x, y))
            }
        }
        // 端のインクから、隣り合うインク（斜めを含む）をたどる
        while let pixel = pending.popLast() {
            for y in (pixel.y - 1)...(pixel.y + 1) {
                for x in (pixel.x - 1)...(pixel.x + 1) where mask[x, y] && !result[x, y] {
                    result[x, y] = true
                    pending.append((x, y))
                }
            }
        }
        return result
    }

    /// その画素が背景だった場合の色（上下の基準の行を直線で補間）
    func expectedColor(_ bitmap: Bitmap, x: Int, y: Int) -> RGB {
        let top = bitmap[x, topRow]
        let bottom = bitmap[x, bottomRow]
        let span = bottomRow - topRow
        let position = y - topRow
        func mix(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Int(from) * (span - position) + Int(to) * position + span / 2) / span)
        }
        return RGB(red: mix(top.red, bottom.red), green: mix(top.green, bottom.green), blue: mix(top.blue, bottom.blue))
    }

    /// インクのある列を、すき間が `gap` px 以下ならつないで、かたまりごとの矩形にする
    static func blobs(in mask: PixelMask, gap: Int) -> [PixelRect] {
        var columns: [(first: Int, last: Int)] = []
        for x in mask.originX..<(mask.originX + mask.width) {
            guard (mask.originY..<(mask.originY + mask.height)).contains(where: { mask[x, $0] }) else { continue }
            if let last = columns.last, x - last.last <= gap {
                columns[columns.count - 1].last = x
            } else {
                columns.append((x, x))
            }
        }
        return columns.compactMap { column in
            let rows = (mask.originY..<(mask.originY + mask.height)).filter { y in
                (column.first...column.last).contains { mask[$0, y] }
            }
            guard let top = rows.first, let bottom = rows.last else { return nil }
            return PixelRect(x: column.first, y: top, width: column.last - column.first + 1, height: bottom - top + 1)
        }
    }

    /// 基準の行が 1 色なら単色。そうでなくても、インク以外がほぼ補間どおりならグラデーション
    private func backgroundKind(_ bitmap: Bitmap, inkCount: Int, noisyCount: Int, blobs: [PixelRect]) -> BackgroundKind {
        let margin = Self.sideMarginPt * scale
        let columns = margin..<(bitmap.width - margin)
        let area = columns.count * max(1, bottomRow - topRow - 1)
        // 文字とアイコンは帯の 1〜2 割を占める。それより大幅に多い・かたまりが多すぎるときは、背景を拾っている
        let inkRatio = Double(inkCount) / Double(area)
        let noisyRatio = Double(noisyCount) / Double(area)
        if inkRatio > 0.35 || noisyRatio > 0.10 || blobs.count > 12 { return .complex }
        let reference = bitmap[bitmap.width / 2, topRow]
        let isFlat = columns.allSatisfy { x in
            bitmap[x, topRow].distance(to: reference) <= Self.noiseThreshold
                && bitmap[x, bottomRow].distance(to: reference) <= Self.noiseThreshold
        }
        return isFlat ? .solid : .gradient
    }
}
