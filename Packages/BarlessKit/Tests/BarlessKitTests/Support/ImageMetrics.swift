import DeviceCatalog
import ImageIOKit

/// 2 枚の画像の、ある範囲での差
struct RegionDifference {
    /// 画素・チャンネルあたりの差の平均（0〜255）
    let meanAbsolute: Double
    /// チャンネルごとの差の最大（0〜255）
    let maxAbsolute: Int
    /// 見て分かる差（3 チャンネルの差の合計が 48 を超える）がある画素の割合
    let visibleRatio: Double
}

enum ImageMetrics {
    /// 見て分かる差とみなす、3 チャンネルの差の合計
    static let visibleThreshold = 48
    /// インクとみなす、背景との差（3 チャンネルの差の合計。実測スクリプトと同じ）
    static let inkThreshold = 60

    static func difference(_ lhs: Bitmap, _ rhs: Bitmap, in rect: PixelRect) -> RegionDifference {
        let area = clamp(rect, to: lhs)
        var total = 0
        var maximum = 0
        var visible = 0
        for y in area.y..<area.maxY {
            for x in area.x..<area.maxX {
                let left = lhs[x, y]
                let right = rhs[x, y]
                let channels = [
                    abs(Int(left.red) - Int(right.red)), abs(Int(left.green) - Int(right.green)), abs(Int(left.blue) - Int(right.blue))
                ]
                total += channels[0] + channels[1] + channels[2]
                maximum = max(maximum, channels.max() ?? 0)
                if channels[0] + channels[1] + channels[2] > visibleThreshold { visible += 1 }
            }
        }
        let count = max(1, area.width * area.height)
        return RegionDifference(
            meanAbsolute: Double(total) / Double(count * 3),
            maxAbsolute: maximum,
            visibleRatio: Double(visible) / Double(count)
        )
    }

    /// インク（背景との差が大きい画素）の重なり具合。両方にある画素 ÷ どちらかにある画素（IoU。1 で完全に一致）
    static func inkOverlap(truth: Bitmap, rendered: Bitmap, background: Bitmap, in rect: PixelRect) -> Double {
        let area = clamp(rect, to: truth)
        var both = 0
        var either = 0
        for y in area.y..<area.maxY {
            for x in area.x..<area.maxX {
                let inTruth = truth[x, y].distance(to: background[x, y]) > inkThreshold
                let inRendered = rendered[x, y].distance(to: background[x, y]) > inkThreshold
                if inTruth && inRendered { both += 1 }
                if inTruth || inRendered { either += 1 }
            }
        }
        return either == 0 ? 1 : Double(both) / Double(either)
    }

    /// インクが載っている範囲（無ければ `nil`）
    static func inkBounds(_ bitmap: Bitmap, background: Bitmap, in rect: PixelRect) -> PixelRect? {
        let area = clamp(rect, to: bitmap)
        var bounds: PixelRect?
        for y in area.y..<area.maxY {
            for x in area.x..<area.maxX where bitmap[x, y].distance(to: background[x, y]) > inkThreshold {
                let pixel = PixelRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    /// 差を色で示した画像。白は差なし、赤が濃いほど差が大きい
    static func heatmap(_ lhs: Bitmap, _ rhs: Bitmap) -> Bitmap {
        var result = Bitmap(width: lhs.width, height: lhs.height, colorSpace: lhs.colorSpace)
        for y in 0..<lhs.height {
            for x in 0..<lhs.width {
                let fade = UInt8(255 - min(255, lhs[x, y].distance(to: rhs[x, y])))
                result[x, y] = RGB(red: 255, green: fade, blue: fade)
            }
        }
        return result
    }

    private static func clamp(_ rect: PixelRect, to bitmap: Bitmap) -> PixelRect {
        rect.intersection(PixelRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
    }
}
