import DeviceCatalog
import ImageIOKit
import StatusBarRenderer

/// 検証結果の画像を作るための、切り出しと並べ方
enum Montage {
    private static let separator = RGB(red: 128, green: 128, blue: 128)

    /// 縦に積む（間に灰色の線を入れる）
    static func stack(_ images: [Bitmap], gap: Int = 4) -> Bitmap {
        let width = images.map(\.width).max() ?? 1
        let height = images.map(\.height).reduce(0, +) + gap * max(0, images.count - 1)
        var result = Bitmap(width: width, height: max(1, height), fill: separator, colorSpace: images.first?.colorSpace)
        var top = 0
        for image in images {
            paste(image, into: &result, x: 0, y: top)
            top += image.height + gap
        }
        return result
    }

    /// 横に並べる（間に灰色の線を入れる）
    static func row(_ images: [Bitmap], gap: Int = 8) -> Bitmap {
        let width = images.map(\.width).reduce(0, +) + gap * max(0, images.count - 1)
        let height = images.map(\.height).max() ?? 1
        var result = Bitmap(width: max(1, width), height: height, fill: separator, colorSpace: images.first?.colorSpace)
        var left = 0
        for image in images {
            paste(image, into: &result, x: left, y: 0)
            left += image.width + gap
        }
        return result
    }

    /// 時刻とアイコンがある範囲（まわり 6pt を含む）だけを切り出して、横に並べる
    static func zones(of bitmap: Bitmap, layout: StatusBarLayout, timeTexts: [String]) -> Bitmap {
        let margin = 6 * layout.scale
        let typography = TimeTypography(layout: layout)
        let rects = timeTexts.map { typography.inkRect(for: $0) }
            + [layout.cellular, layout.wifi, layout.battery]
            + [layout.carrier].compactMap { $0 }
        var ranges: [ClosedRange<Int>] = []
        for rect in rects.sorted(by: { $0.x < $1.x }) {
            let range = max(0, rect.x - margin)...min(bitmap.width - 1, rect.maxX + margin)
            if let last = ranges.last, last.upperBound >= range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                ranges.append(range)
            }
        }
        let top = max(0, layout.inkTop - margin)
        let height = min(bitmap.height, layout.inkBottom + margin) - top
        return row(ranges.map { bitmap.cropped(x: $0.lowerBound, y: top, width: $0.count, height: height) })
    }

    /// 帯の高さ（まわり 6pt を含む）で、`centerX` の左右 `halfWidthPt` を切り出す
    static func window(of bitmap: Bitmap, layout: StatusBarLayout, centerX: Int, halfWidthPt: Int) -> Bitmap {
        let margin = 6 * layout.scale
        let top = max(0, layout.inkTop - margin)
        let height = min(bitmap.height, layout.inkBottom + margin) - top
        let left = max(0, centerX - halfWidthPt * layout.scale)
        let right = min(bitmap.width, centerX + halfWidthPt * layout.scale)
        return bitmap.cropped(x: left, y: top, width: right - left, height: height)
    }

    private static func paste(_ image: Bitmap, into canvas: inout Bitmap, x: Int, y: Int) {
        for row in 0..<image.height {
            for column in 0..<image.width {
                canvas[x + column, y + row] = image[column, row]
            }
        }
    }
}
