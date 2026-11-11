import ImageIOKit
import InpaintEngine
import Testing

struct InpaintEngineTests {
    /// 横・縦・斜めに直線的に変わる背景を作る
    private func gradient(width: Int, height: Int, horizontal: Int, vertical: Int) -> Bitmap {
        var bitmap = Bitmap(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8(min(255, 20 + horizontal * x + vertical * y))
                bitmap[x, y] = RGB(red: value, green: UInt8(255 - Int(value)), blue: 128)
            }
        }
        return bitmap
    }

    /// 背景に黒い四角を描き、その四角を覆うマスクを返す
    private func stamp(on background: Bitmap, x: Int, y: Int, size: Int) -> (image: Bitmap, mask: PixelMask) {
        var image = background
        var mask = PixelMask(originX: 0, originY: 0, width: background.width, height: background.height)
        for row in y..<(y + size) {
            for column in x..<(x + size) {
                image[column, row] = .black
                mask[column, row] = true
            }
        }
        return (image, mask)
    }

    private func maxDifference(_ lhs: Bitmap, _ rhs: Bitmap) -> Int {
        zip(lhs.data, rhs.data).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    @Test
    func solidFillRestoresFlatBackground() {
        let background = Bitmap(width: 30, height: 20, fill: RGB(red: 242, green: 242, blue: 247))
        let (image, mask) = stamp(on: background, x: 10, y: 6, size: 8)
        #expect(SolidFillInpainter().fill(image, mask: mask).data == background.data)
    }

    /// 直線的に変わるグラデーションは、横・縦・斜めのどれでも元どおりになる（丸めの 1 段階まで）
    @Test(arguments: [(3, 0), (0, 5), (2, 4)])
    func gradientFillRestoresLinearGradient(horizontal: Int, vertical: Int) {
        let background = gradient(width: 40, height: 24, horizontal: horizontal, vertical: vertical)
        let (image, mask) = stamp(on: background, x: 12, y: 7, size: 10)
        let restored = GradientInpainter().fill(image, mask: mask)
        #expect(maxDifference(restored, background) <= 1)
    }

    @Test
    func gradientFillWorksAtImageEdge() {
        let background = gradient(width: 30, height: 20, horizontal: 0, vertical: 6)
        // 左上の角にかかるマスク。左と上には背景が無いので、右と下だけから埋める
        let (image, mask) = stamp(on: background, x: 0, y: 0, size: 6)
        let restored = GradientInpainter().fill(image, mask: mask)
        #expect(maxDifference(restored, background) <= 30)
        #expect(restored[2, 2] != .black)
    }

    @Test
    func leavesPixelsOutsideMaskUntouched() async throws {
        let background = gradient(width: 30, height: 20, horizontal: 2, vertical: 3)
        let (image, mask) = stamp(on: background, x: 10, y: 6, size: 5)
        let inpainters: [any Inpainter] = [SolidFillInpainter(), GradientInpainter()]
        for inpainter in inpainters {
            let restored = try await inpainter.inpaint(image, mask: mask)
            for y in 0..<image.height {
                for x in 0..<image.width where !mask[x, y] {
                    #expect(restored[x, y] == image[x, y])
                }
            }
        }
    }

    /// マスクが画像の外にあるときは、落ちずに画像をそのまま返す
    @Test
    func maskOutsideImageChangesNothing() {
        let background = gradient(width: 10, height: 10, horizontal: 5, vertical: 5)
        var mask = PixelMask(originX: 20, originY: 3, width: 2, height: 2)
        mask[20, 3] = true
        #expect(SolidFillInpainter().fill(background, mask: mask).data == background.data)
        #expect(GradientInpainter().fill(background, mask: mask).data == background.data)
        var below = PixelMask(originX: 2, originY: 30, width: 2, height: 2)
        below[2, 30] = true
        #expect(SolidFillInpainter().fill(background, mask: below).data == background.data)
        #expect(GradientInpainter().fill(background, mask: below).data == background.data)
    }

    @Test
    func emptyMaskChangesNothing() {
        let background = gradient(width: 10, height: 10, horizontal: 5, vertical: 5)
        let mask = PixelMask(originX: 2, originY: 2, width: 4, height: 4)
        #expect(GradientInpainter().fill(background, mask: mask).data == background.data)
        #expect(SolidFillInpainter().fill(background, mask: mask).data == background.data)
    }
}
