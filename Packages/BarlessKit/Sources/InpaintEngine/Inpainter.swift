import CoreGraphics
import ImageIOKit

/// 画像の一部を、まわりの背景から作った色で埋める処理。
///
/// MVP は単色（`SolidFillInpainter`）とグラデーション（`GradientInpainter`）。
/// 写真・壁紙の背景は Phase 2 で Core ML のモデルを足す想定なので、呼び出しは `async` にしている（仕様書 §7）。
public protocol Inpainter: Sendable {
    /// `mask` が `true` の画素を埋めた画像を返す。マスクの外の画素は変えない
    func inpaint(_ bitmap: Bitmap, mask: PixelMask) async throws -> Bitmap
}

extension Inpainter {
    /// `CGImage` のまま渡す版
    public func inpaint(_ image: CGImage, mask: PixelMask) async throws -> CGImage {
        try await inpaint(Bitmap(cgImage: image), mask: mask).makeCGImage()
    }
}
