import CoreGraphics
import DeviceCatalog
import ImageIOKit

/// 画像の右下に、小さく文字（アプリ名）を載せる透かし。
///
/// 文字はシステムフォントの輪郭で描く。下の画像の明るさを見て、黒か白の半透明にする
/// （明るい画面でも、暗い写真でも読めるように）
public struct WatermarkRenderer: Sendable {
    /// 文字の大きさ。画像の幅に対する割合（幅 393pt の画面で 11pt ほど）
    static let fontRatio: CGFloat = 0.029
    /// 画像の右端と下端から空ける幅。画像の幅に対する割合。
    /// 下端の中央にあるホームインジケーターには重ならない（右端に寄せ、インジケーターより上に置く）
    static let marginRatio: CGFloat = 0.04
    /// 文字がこれより小さくなる画像（幅がとても狭い画像）には、描かない（px）
    static let minimumFontSize: CGFloat = 6
    /// 文字の太さ（システムフォントの semibold）
    static let weight: CGFloat = 0.3
    /// 文字の濃さ
    static let alpha: CGFloat = 0.55
    /// 下の画像の明るさ（0〜255）がこれより明るければ、黒い文字にする
    static let lightBackgroundLuma = 140.0

    public init() {}

    /// 透かしを描く。文字が空のとき・画像が小さすぎて入らないときは、何もしない
    public func draw(_ text: String, into bitmap: inout Bitmap) throws {
        guard let placement = placement(of: text, width: bitmap.width, height: bitmap.height) else { return }
        let gray: CGFloat = Self.averageLuma(of: bitmap, in: placement.frame) > Self.lightBackgroundLuma ? 0 : 1
        try bitmap.draw { context in
            context.setShouldAntialias(true)
            context.addPath(placement.path)
            context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: Self.alpha))
            context.fillPath()
        }
    }

    /// 透かしの文字が載る範囲（px）。描かないときは `nil`
    public func frame(of text: String, width: Int, height: Int) -> PixelRect? {
        placement(of: text, width: width, height: height)?.frame
    }

    /// 文字の輪郭（px 座標・左上が原点）と、それを囲む範囲
    private func placement(of text: String, width: Int, height: Int) -> (path: CGPath, frame: PixelRect)? {
        let fontSize = CGFloat(width) * Self.fontRatio
        guard fontSize >= Self.minimumFontSize else { return nil }
        let outline = TextOutline(text: text, fontSize: fontSize, weight: Self.weight)
        guard !outline.path.isEmpty else { return nil }
        let margin = CGFloat(width) * Self.marginRatio
        // 輪郭は上向きが正なので、上下を返して、右下の余白の内側に置く
        var transform = CGAffineTransform(
            translationX: CGFloat(width) - margin - outline.bounds.maxX,
            y: CGFloat(height) - margin + outline.bounds.minY
        ).scaledBy(x: 1, y: -1)
        guard let path = outline.path.copy(using: &transform) else { return nil }
        let bounds = path.boundingBoxOfPath.integral
        let frame = PixelRect(x: Int(bounds.minX), y: Int(bounds.minY), width: Int(bounds.width), height: Int(bounds.height))
        guard frame.x >= 0, frame.y >= 0, frame.maxX <= width, frame.maxY <= height, !frame.isEmpty else { return nil }
        return (path, frame)
    }

    /// 範囲の中の、明るさの平均（0〜255）
    private static func averageLuma(of bitmap: Bitmap, in rect: PixelRect) -> Double {
        var total = 0.0
        for y in rect.y..<rect.maxY {
            for x in rect.x..<rect.maxX {
                total += bitmap[x, y].luma
            }
        }
        return total / Double(max(1, rect.width * rect.height))
    }
}
