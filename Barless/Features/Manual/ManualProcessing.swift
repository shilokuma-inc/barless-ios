import CoreGraphics
import Foundation
import ImageIOKit
import StatusBarEditor

/// 手動調整の画面で使う画像
nonisolated struct ManualCanvas: Sendable {
    /// 元の大きさの画像
    let original: CGImage
    let editor: ManualEditor
    /// 上端の切り出し（帯の高さの上限まで）。調整の途中の結果は、これだけに当てて作る
    let strip: Bitmap
}

/// 調整の途中の結果
nonisolated struct ManualPreview: Sendable {
    /// 上端の切り出しに、調整を当てた画像。元の画像の上端に重ねて出す
    let strip: CGImage
    /// 消した跡が残りそうか
    let mayLeaveTraces: Bool
}

/// 手動調整の画像の処理。BarlessKit の `ManualEditor` を呼ぶ。処理はすべて端末の中で行う
nonisolated struct ManualProcessor: Sendable {
    /// 元の大きさで読み込んで、上端を切り出す
    @concurrent
    func load(_ source: ManualSource) async throws -> ManualCanvas {
        let original = try ImageDecoder.decode(data: source.imageData)
        let editor = ManualEditor(pixelWidth: original.width, pixelHeight: original.height)
        let top = CGRect(x: 0, y: 0, width: original.width, height: editor.stripHeight)
        guard let cropped = original.cropping(to: top) else { throw BitmapError.imageCreationFailed }
        return ManualCanvas(original: original, editor: editor, strip: try Bitmap(cgImage: cropped))
    }

    /// 上端の切り出しに調整を当てる。帯の中しか読み書きしないので、全体に当てた結果の上端と同じになる
    @concurrent
    func preview(_ adjustment: ManualAdjustment, on canvas: ManualCanvas) async throws -> ManualPreview {
        let result = canvas.editor.apply(adjustment, to: canvas.strip)
        return ManualPreview(strip: try result.bitmap.makeCGImage(), mayLeaveTraces: result.mayLeaveTraces)
    }

    /// 画像の全体に調整を当てて、エディタと書き出しで使う結果にする
    @concurrent
    func apply(
        _ adjustment: ManualAdjustment, to canvas: ManualCanvas, source: ManualSource, outcome: HideOutcome
    ) async throws -> EditedScreenshot {
        let result = canvas.editor.apply(adjustment, to: try Bitmap(cgImage: canvas.original))
        return EditedScreenshot(
            before: canvas.original,
            after: try result.bitmap.makeCGImage(),
            tidied: nil,
            outcome: outcome,
            manualSource: source,
            manual: ManualEdit(adjustment: adjustment, mayLeaveTraces: result.mayLeaveTraces)
        )
    }

    /// 画像のその位置（px）の色。画像の外なら `nil`
    func color(in canvas: ManualCanvas, x: Int, y: Int) -> RGB? {
        let original = canvas.original
        guard x >= 0, y >= 0, x < original.width, y < original.height else { return nil }
        if y < canvas.strip.height { return canvas.strip[x, y] }
        guard let pixel = original.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        return (try? Bitmap(cgImage: pixel))?[0, 0]
    }
}
