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

/// ステータスバーの帯から拾った「インク」（文字・アイコン）
public struct InkScan: Sendable, Equatable {
    /// インクの画素。帯の範囲だけを覆う
    public let mask: PixelMask
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

    func scan(_ bitmap: Bitmap) -> InkScan {
        let margin = Self.sideMarginPt * scale
        // 帯が入りきらない画像（上端の切り出しが短すぎる・幅が狭すぎる）では、何も拾わない
        guard bottomRow > topRow + 1, bitmap.width > 2 * margin else {
            let empty = PixelMask(originX: 0, originY: topRow, width: max(1, bitmap.width), height: 1)
            return InkScan(mask: empty, blobs: [], background: .complex, inkIsDark: true)
        }
        var mask = PixelMask(originX: 0, originY: topRow + 1, width: bitmap.width, height: max(1, bottomRow - topRow - 1))
        var noisy = 0
        var darker = 0
        var lighter = 0
        for y in (topRow + 1)..<bottomRow {
            for x in margin..<(bitmap.width - margin) {
                let pixel = bitmap[x, y]
                let expected = expectedColor(bitmap, x: x, y: y)
                let difference = pixel.distance(to: expected)
                if difference > Self.inkThreshold {
                    mask[x, y] = true
                    if pixel.luma < expected.luma { darker += 1 } else { lighter += 1 }
                } else if difference > Self.noiseThreshold {
                    noisy += 1
                }
            }
        }
        let blobs = Self.blobs(in: mask, gap: Self.blobGapPt * scale)
        let kind = backgroundKind(bitmap, inkCount: darker + lighter, noisyCount: noisy, blobs: blobs)
        return InkScan(mask: mask, blobs: blobs, background: kind, inkIsDark: darker >= lighter)
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
