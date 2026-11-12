import ImageIOKit
import InpaintEngine
import Testing

/// 帯のぼかしの、平均のとり方
struct BandBlurTests {
    /// 1 色の画像は、ぼかしても変わらない（端の扱いで色がずれない）
    @Test
    func keepsFlatColor() {
        let color = RGB(red: 31, green: 127, blue: 233)
        let bitmap = Bitmap(width: 40, height: 30, fill: color)

        let blurred = BandBlur().blur(bitmap, bandHeight: 20)

        #expect(blurred.data == bitmap.data)
    }

    /// 帯の下の行は、読みも書きもしない
    @Test
    func ignoresRowsBelowBand() {
        var bitmap = Bitmap(width: 40, height: 30, fill: .white)
        for x in 0..<40 {
            bitmap[x, 20] = .black
        }

        let blurred = BandBlur().blur(bitmap, bandHeight: 20)

        #expect(blurred.data == bitmap.data)
    }

    /// 帯より低い画像でも、ある行だけをぼかす
    @Test
    func clampsBandToImageHeight() {
        var bitmap = Bitmap(width: 20, height: 6, fill: .white)
        bitmap[10, 3] = .black

        let blurred = BandBlur().blur(bitmap, bandHeight: 100)

        #expect(blurred.width == 20 && blurred.height == 6)
        #expect(blurred[10, 3] != .black)
    }
}
