import CoreGraphics
import Foundation

/// 1 画素の色（8bit）。値は画像の色空間のまま扱い、変換しない
public struct RGB: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    @inlinable
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = RGB(red: 0, green: 0, blue: 0)
    public static let white = RGB(red: 255, green: 255, blue: 255)

    /// 3 チャンネルの差の絶対値の合計（0〜765）
    @inlinable
    public func distance(to other: RGB) -> Int {
        abs(Int(red) - Int(other.red)) + abs(Int(green) - Int(other.green)) + abs(Int(blue) - Int(other.blue))
    }

    /// 明るさ（0〜255。Rec. 601 の重み）
    public var luma: Double {
        0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
    }
}

public enum BitmapError: Error, Equatable {
    case emptyImage
    case contextCreationFailed
    case imageCreationFailed
}

/// 8bit RGBX のビットマップ。左上が原点で、行優先に並ぶ。
///
/// スクリーンショットは不透明なのでアルファは持たない。色空間は元の画像のものを引き継ぎ、
/// 画素の値を変換せずに読み書きする（実機のスクリーンショットは Display P3、Simulator は sRGB）。
public struct Bitmap: @unchecked Sendable {
    public static let bytesPerPixel = 4

    public let width: Int
    public let height: Int
    /// R, G, B, X の順で 1 画素 4 バイト
    public var data: [UInt8] { storage }
    /// 画素の読み書きをモジュールの外からもインライン展開できるように、入れ物は `@usableFromInline` にしている
    @usableFromInline var storage: [UInt8]
    public let colorSpace: CGColorSpace

    public init(width: Int, height: Int, fill: RGB = .white, colorSpace: CGColorSpace? = nil) {
        precondition(width > 0 && height > 0, "大きさは 1 以上にする")
        self.width = width
        self.height = height
        self.colorSpace = colorSpace ?? Self.sRGB
        var data = [UInt8](repeating: 255, count: width * height * Self.bytesPerPixel)
        for index in 0..<(width * height) {
            data[index * 4] = fill.red
            data[index * 4 + 1] = fill.green
            data[index * 4 + 2] = fill.blue
        }
        self.storage = data
    }

    /// `CGImage` を 1:1 で読み込む。RGB の色空間はそのまま使い、それ以外（グレー・インデックスなど）は sRGB に変換する
    public init(cgImage: CGImage) throws {
        guard cgImage.width > 0, cgImage.height > 0 else { throw BitmapError.emptyImage }
        let width = cgImage.width
        let height = cgImage.height
        var data = [UInt8](repeating: 255, count: width * height * Self.bytesPerPixel)
        let candidates = [cgImage.colorSpace].compactMap { $0 }.filter { $0.model == .rgb } + [Self.sRGB]
        var used: CGColorSpace?
        for space in candidates where used == nil {
            let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = Self.makeContext(buffer: buffer, width: width, height: height, colorSpace: space) else {
                    return false
                }
                context.interpolationQuality = .none
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            if drawn { used = space }
        }
        guard let used else { throw BitmapError.contextCreationFailed }
        self.width = width
        self.height = height
        self.storage = data
        self.colorSpace = used
    }

    @inlinable
    public subscript(x: Int, y: Int) -> RGB {
        get {
            let offset = (y * width + x) * Self.bytesPerPixel
            return RGB(red: storage[offset], green: storage[offset + 1], blue: storage[offset + 2])
        }
        set {
            let offset = (y * width + x) * Self.bytesPerPixel
            storage[offset] = newValue.red
            storage[offset + 1] = newValue.green
            storage[offset + 2] = newValue.blue
        }
    }

    @inlinable
    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// 矩形で切り出す（画像からはみ出す部分は切り詰める）
    public func cropped(x: Int, y: Int, width cropWidth: Int, height cropHeight: Int) -> Bitmap {
        let minX = max(0, x)
        let minY = max(0, y)
        let maxX = min(width, x + cropWidth)
        let maxY = min(height, y + cropHeight)
        precondition(maxX > minX && maxY > minY, "切り出す範囲が画像の外にある")
        var result = Bitmap(width: maxX - minX, height: maxY - minY, colorSpace: colorSpace)
        let rowBytes = result.width * Self.bytesPerPixel
        for row in 0..<result.height {
            let source = ((minY + row) * width + minX) * Self.bytesPerPixel
            result.storage.replaceSubrange((row * rowBytes)..<((row + 1) * rowBytes), with: storage[source..<(source + rowBytes)])
        }
        return result
    }

    /// 縦横を整数倍に拡大する（なめらかに補間する）
    public func enlarged(by factor: Int) throws -> Bitmap {
        precondition(factor >= 1, "倍率は 1 以上にする")
        var result = Bitmap(width: width * factor, height: height * factor, colorSpace: colorSpace)
        let source = try makeCGImage()
        let size = CGSize(width: result.width, height: result.height)
        try result.draw { context in
            context.interpolationQuality = .high
            // draw(_:) の座標は上下を反転してあるので、画像を描くときだけ元に戻す
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(source, in: CGRect(origin: .zero, size: size))
        }
        return result
    }

    /// Core Graphics で描き込む。座標は左上が原点・下向きが正（画素の並びと同じ）にそろえてある
    public mutating func draw(_ body: (CGContext) -> Void) throws {
        let width = width
        let height = height
        let colorSpace = colorSpace
        let drawn = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = Self.makeContext(buffer: buffer, width: width, height: height, colorSpace: colorSpace) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            body(context)
            return true
        }
        if !drawn { throw BitmapError.contextCreationFailed }
    }

    public func makeCGImage() throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { throw BitmapError.imageCreationFailed }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * Self.bytesPerPixel,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { throw BitmapError.imageCreationFailed }
        return image
    }

    private static var sRGB: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private static func makeContext(
        buffer: UnsafeMutableRawBufferPointer,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CGContext? {
        CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    }
}
