import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, Equatable {
    case cannotDecode
    case cannotEncode
}

public enum ImageFileFormat: String, Sendable, CaseIterable {
    case png
    case heic

    var typeIdentifier: CFString {
        switch self {
        case .png: UTType.png.identifier as CFString
        case .heic: UTType.heic.identifier as CFString
        }
    }
}

/// 画像の読み込み。処理はすべて端末の中で行う
public enum ImageDecoder {
    /// 原寸で読み込む
    public static func decode(data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageCodecError.cannotDecode
        }
        return image
    }

    public static func decode(contentsOf url: URL) throws -> CGImage {
        try decode(data: Data(contentsOf: url))
    }

    /// 長辺が `maxPixelSize` 以下になるように縮小して読み込む（プレビュー用。原寸を展開しないのでメモリを抑えられる）
    public static func decodeThumbnail(data: Data, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageCodecError.cannotDecode
        }
        return image
    }
}

/// 書き出しの設定
public struct ExportOptions: Sendable, Equatable {
    public var format: ImageFileFormat
    /// メタデータの Software 欄に書くアプリ名。`nil` なら書かない（仕様書 §5-4a）
    public var softwareName: String?
    /// HEIC の画質（0〜1）。PNG では使わない
    public var lossyQuality: Double

    public init(format: ImageFileFormat = .png, softwareName: String? = nil, lossyQuality: Double = 0.9) {
        self.format = format
        self.softwareName = softwareName
        self.lossyQuality = lossyQuality
    }
}

/// 画像の書き出し。
///
/// 画素から作り直した `CGImage` だけを書くので、元のファイルのメタデータ（位置情報・撮影日時など）は引き継がない。
public enum ImageEncoder {
    public static func encode(_ image: CGImage, options: ExportOptions = ExportOptions()) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, options.format.typeIdentifier, 1, nil) else {
            throw ImageCodecError.cannotEncode
        }
        var properties: [CFString: Any] = [:]
        if let softwareName = options.softwareName {
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFSoftware: softwareName]
            if options.format == .png {
                properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGSoftware: softwareName]
            }
        }
        if options.format == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = options.lossyQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.cannotEncode }
        return output as Data
    }
}

/// メタデータの読み取り（書き出した結果の確認用）
public enum ImageMetadata {
    /// ImageIO が返すプロパティ（`kCGImageProperty…` をキーにした辞書）
    public static func properties(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return [:]
        }
        return properties
    }

    /// Software 欄の値（TIFF または PNG の辞書から）
    public static func softwareName(of data: Data) -> String? {
        let properties = properties(of: data)
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
        return (tiff?[kCGImagePropertyTIFFSoftware as String] as? String)
            ?? (png?[kCGImagePropertyPNGSoftware as String] as? String)
    }

    /// 位置情報（GPS の辞書）が入っているか
    public static func hasLocation(_ data: Data) -> Bool {
        properties(of: data)[kCGImagePropertyGPSDictionary as String] != nil
    }
}
