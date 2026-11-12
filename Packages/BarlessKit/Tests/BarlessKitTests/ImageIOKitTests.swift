import BarlessTestSupport
import CoreGraphics
import Foundation
import ImageIO
import ImageIOKit
import Testing
import UniformTypeIdentifiers

struct BitmapTests {
    @Test
    func keepsPixelValuesThroughCGImage() throws {
        var bitmap = Bitmap(width: 4, height: 3, fill: RGB(red: 10, green: 20, blue: 30))
        bitmap[1, 2] = RGB(red: 200, green: 100, blue: 50)
        let restored = try Bitmap(cgImage: bitmap.makeCGImage())
        #expect(restored.width == 4)
        #expect(restored.height == 3)
        #expect(restored[0, 0] == RGB(red: 10, green: 20, blue: 30))
        #expect(restored[1, 2] == RGB(red: 200, green: 100, blue: 50))
    }

    /// 実機のスクリーンショットは Display P3。色を変換せずに読めること（背景は P3 の値で 242, 242, 246）
    @Test
    func keepsDisplayP3ColorSpace() throws {
        let fixture = try #require(try Fixtures.all().first { $0.variant == "light-real" })
        let strip = try fixture.loadStrip()
        #expect(strip.colorSpace.name == CGColorSpace.displayP3)
        #expect(strip[strip.width / 2, 12] == RGB(red: 242, green: 242, blue: 246))
        let restored = try Bitmap(cgImage: strip.makeCGImage())
        #expect(restored.colorSpace.name == CGColorSpace.displayP3)
        #expect(restored.data == strip.data)
    }

    @Test
    func drawsWithTopLeftOrigin() throws {
        var bitmap = Bitmap(width: 6, height: 6, fill: .white)
        try bitmap.draw { context in
            context.setShouldAntialias(false)
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        }
        #expect(bitmap[0, 0] == .black)
        #expect(bitmap[1, 0] == .black)
        #expect(bitmap[2, 0] == .white)
        #expect(bitmap[0, 1] == .white)
        #expect(bitmap[0, 5] == .white)
    }

    @Test
    func cropsAndEnlarges() throws {
        var bitmap = Bitmap(width: 8, height: 8, fill: .white)
        bitmap[5, 6] = .black
        let crop = bitmap.cropped(x: 4, y: 4, width: 10, height: 10)
        #expect(crop.width == 4)
        #expect(crop.height == 4)
        #expect(crop[1, 2] == .black)
        let enlarged = try crop.enlarged(by: 3)
        #expect(enlarged.width == 12)
        #expect(enlarged.height == 12)
        // 上下が反転していないこと（黒い画素は下半分に残る）
        #expect(enlarged[4, 7].luma < 128)
        #expect(enlarged[4, 1].luma > 200)
    }
}

struct PixelMaskTests {
    @Test
    func dilatesWithinItsRegion() {
        var mask = PixelMask(originX: 10, originY: 20, width: 5, height: 5)
        mask[12, 22] = true
        #expect(mask.count == 1)
        #expect(mask[0, 0] == false)
        let dilated = mask.dilated(by: 1)
        #expect(dilated.count == 9)
        #expect(dilated[11, 21])
        #expect(dilated[13, 23])
        #expect(dilated[10, 20] == false)
        // 範囲の外には広がらない
        #expect(mask.dilated(by: 10).count == 25)
    }
}

struct ImageCodecTests {
    private func sample() throws -> CGImage {
        var bitmap = Bitmap(width: 40, height: 20, fill: RGB(red: 240, green: 240, blue: 245))
        bitmap[3, 4] = RGB(red: 1, green: 2, blue: 3)
        return try bitmap.makeCGImage()
    }

    @Test
    func pngRoundTripIsLossless() throws {
        let data = try ImageEncoder.encode(sample())
        let restored = try Bitmap(cgImage: ImageDecoder.decode(data: data))
        #expect(restored[3, 4] == RGB(red: 1, green: 2, blue: 3))
        #expect(restored[0, 0] == RGB(red: 240, green: 240, blue: 245))
    }

    /// Software 欄にアプリ名を書ける。指定しなければ書かない。位置情報は入らない（仕様書 §5-4a）
    @Test
    func writesSoftwareNameOnlyWhenRequested() throws {
        let named = try ImageEncoder.encode(sample(), options: ExportOptions(softwareName: "Barless"))
        #expect(ImageMetadata.softwareName(of: named) == "Barless")
        #expect(ImageMetadata.hasLocation(named) == false)
        let plain = try ImageEncoder.encode(sample())
        #expect(ImageMetadata.softwareName(of: plain) == nil)
    }

    @Test
    func decodesThumbnailWithinMaxSize() throws {
        let data = try ImageEncoder.encode(sample())
        let thumbnail = try ImageDecoder.decodeThumbnail(data: data, maxPixelSize: 10)
        #expect(max(thumbnail.width, thumbnail.height) == 10)
    }

    /// 向きの情報が付いた画像（カメラの写真など）は、見たとおりの向きで読む
    @Test
    func appliesOrientationWhenDecoding() throws {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        // 6 = 時計回りに 90 度回して表示する
        CGImageDestinationAddImage(destination, try sample(), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let image = try ImageDecoder.decode(data: output as Data)

        #expect(image.width == 20 && image.height == 40)
    }

    /// HEIC でも書き出せて、Software 欄も残る
    @Test
    func encodesHEIC() throws {
        let data = try ImageEncoder.encode(sample(), options: ExportOptions(format: .heic, softwareName: "Barless"))
        let image = try ImageDecoder.decode(data: data)
        #expect(image.width == 40 && image.height == 20)
        #expect(ImageMetadata.softwareName(of: data) == "Barless")
    }

    @Test
    func rejectsBrokenData() {
        #expect(throws: ImageCodecError.cannotDecode) {
            try ImageDecoder.decode(data: Data([0, 1, 2, 3]))
        }
    }
}
