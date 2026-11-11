import ImageIOKit

/// 単色の背景用。マスクのまわり（マスクが覆う矩形の中で、マスクされていない画素）の中央値の色で塗る
public struct SolidFillInpainter: Inpainter {
    public init() {}

    public func inpaint(_ bitmap: Bitmap, mask: PixelMask) async throws -> Bitmap {
        fill(bitmap, mask: mask)
    }

    /// 同期版
    public func fill(_ bitmap: Bitmap, mask: PixelMask) -> Bitmap {
        guard let area = Self.overlap(of: bitmap, and: mask), let color = backgroundColor(of: bitmap, mask: mask) else {
            return bitmap
        }
        var result = bitmap
        for y in area.rows {
            for x in area.columns where mask[x, y] {
                result[x, y] = color
            }
        }
        return result
    }

    /// マスクが覆う矩形の中で、マスクされていない画素の中央値（チャンネルごと）
    func backgroundColor(of bitmap: Bitmap, mask: PixelMask) -> RGB? {
        guard let area = Self.overlap(of: bitmap, and: mask) else { return nil }
        var reds: [UInt8] = []
        var greens: [UInt8] = []
        var blues: [UInt8] = []
        for y in area.rows {
            for x in area.columns where !mask[x, y] {
                let pixel = bitmap[x, y]
                reds.append(pixel.red)
                greens.append(pixel.green)
                blues.append(pixel.blue)
            }
        }
        guard !reds.isEmpty else { return nil }
        reds.sort()
        greens.sort()
        blues.sort()
        return RGB(red: reds[reds.count / 2], green: greens[greens.count / 2], blue: blues[blues.count / 2])
    }

    /// 画像とマスクが重なる範囲。重ならなければ `nil`（マスクが画像の外にあるとき）
    private static func overlap(of bitmap: Bitmap, and mask: PixelMask) -> (columns: Range<Int>, rows: Range<Int>)? {
        let minX = max(0, mask.originX)
        let maxX = min(bitmap.width, mask.originX + mask.width)
        let minY = max(0, mask.originY)
        let maxY = min(bitmap.height, mask.originY + mask.height)
        guard minX < maxX, minY < maxY else { return nil }
        return (minX..<maxX, minY..<maxY)
    }
}
