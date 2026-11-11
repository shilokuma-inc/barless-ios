import ImageIOKit

/// グラデーションの背景用。マスクされた画素を、同じ行の左右と同じ列の上下にある背景の画素から補間して埋める。
///
/// - 行ごと・列ごとに「マスクの切れ目の両端の色」を直線でつなぐ（1 次の補間）
/// - 横と縦の結果を、切れ目が短いほうを重く見て混ぜる（文字の細い線は横、電池のような広い面は縦が効く）
/// - 色が直線的に変わるグラデーション（縦・横・斜め）は元どおりになる。模様や輪郭がある背景では、その部分がぼやける
public struct GradientInpainter: Inpainter {
    public init() {}

    public func inpaint(_ bitmap: Bitmap, mask: PixelMask) async throws -> Bitmap {
        fill(bitmap, mask: mask)
    }

    /// 同期版
    public func fill(_ bitmap: Bitmap, mask: PixelMask) -> Bitmap {
        let minX = max(0, mask.originX)
        let minY = max(0, mask.originY)
        let maxX = min(bitmap.width, mask.originX + mask.width)
        let maxY = min(bitmap.height, mask.originY + mask.height)
        guard maxX > minX, maxY > minY else { return bitmap }
        var blend = Blend(minX: minX, minY: minY, width: maxX - minX, height: maxY - minY)
        for y in minY..<maxY {
            let line = (minX..<maxX).map { mask[$0, y] }
            for run in Self.runs(in: line) {
                let before = minX + run.lowerBound - 1
                let after = minX + run.upperBound
                let start = before >= 0 ? bitmap[before, y] : nil
                let end = after < bitmap.width ? bitmap[after, y] : nil
                for offset in run {
                    let segment = Segment(from: start, to: end, position: offset - run.lowerBound + 1, span: run.count + 1)
                    blend.add(segment, x: minX + offset, y: y)
                }
            }
        }
        for x in minX..<maxX {
            let line = (minY..<maxY).map { mask[x, $0] }
            for run in Self.runs(in: line) {
                let before = minY + run.lowerBound - 1
                let after = minY + run.upperBound
                let start = before >= 0 ? bitmap[x, before] : nil
                let end = after < bitmap.height ? bitmap[x, after] : nil
                for offset in run {
                    let segment = Segment(from: start, to: end, position: offset - run.lowerBound + 1, span: run.count + 1)
                    blend.add(segment, x: x, y: minY + offset)
                }
            }
        }
        var result = bitmap
        for y in minY..<maxY {
            for x in minX..<maxX where mask[x, y] {
                if let color = blend.color(x: x, y: y) { result[x, y] = color }
            }
        }
        return result
    }

    /// `true` が続く範囲
    static func runs(in line: [Bool]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?
        for (index, value) in line.enumerated() {
            if value, start == nil { start = index }
            if !value, let begin = start {
                result.append(begin..<index)
                start = nil
            }
        }
        if let begin = start { result.append(begin..<line.count) }
        return result
    }
}

/// マスクの切れ目 1 つの中での位置。両端の色 `from`・`to`（画像の外なら `nil`）の間の、`position / span` のところ
private struct Segment {
    let from: RGB?
    let to: RGB?
    let position: Int
    let span: Int
}

/// 横と縦の補間の結果を、重み付きで足し合わせる入れ物
private struct Blend {
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int
    private var sums: [Double]
    private var weights: [Double]

    init(minX: Int, minY: Int, width: Int, height: Int) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
        self.sums = [Double](repeating: 0, count: width * height * 3)
        self.weights = [Double](repeating: 0, count: width * height)
    }

    /// 切れ目の中の位置に応じて補間した色を足す。端が画像の外なら、ある側の色をそのまま使う
    mutating func add(_ segment: Segment, x: Int, y: Int) {
        guard let near = segment.from ?? segment.to else { return }
        let far = segment.to ?? near
        let start = segment.from ?? near
        let ratio = Double(segment.position) / Double(segment.span)
        // 片側しか無いときは、その分だけ信頼を下げる
        let weight = (segment.from != nil && segment.to != nil ? 1.0 : 0.25) / Double(segment.span)
        let index = (y - minY) * width + (x - minX)
        sums[index * 3] += weight * (Double(start.red) + (Double(far.red) - Double(start.red)) * ratio)
        sums[index * 3 + 1] += weight * (Double(start.green) + (Double(far.green) - Double(start.green)) * ratio)
        sums[index * 3 + 2] += weight * (Double(start.blue) + (Double(far.blue) - Double(start.blue)) * ratio)
        weights[index] += weight
    }

    func color(x: Int, y: Int) -> RGB? {
        let index = (y - minY) * width + (x - minX)
        guard weights[index] > 0 else { return nil }
        func channel(_ offset: Int) -> UInt8 {
            UInt8(min(255, max(0, (sums[index * 3 + offset] / weights[index]).rounded())))
        }
        return RGB(red: channel(0), green: channel(1), blue: channel(2))
    }
}
