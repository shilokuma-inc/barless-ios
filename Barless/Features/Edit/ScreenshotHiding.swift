import CoreGraphics
import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarEditor

/// 画面に出す 1 枚分の結果
nonisolated struct EditedScreenshot: Sendable {
    /// 元の画像（見比べる用）
    let before: CGImage
    /// ステータスバーを消した画像。消せなかったときは `before` と同じ
    let after: CGImage
    let outcome: HideOutcome

    /// 消せたときの情報
    var hidden: HiddenStatusBar? {
        if case let .hidden(hidden) = outcome { return hidden }
        return nil
    }
}

/// 選んだ画像のステータスバーを隠す処理。画面のテストで差し替えられるようにしている
nonisolated protocol ScreenshotHiding: Sendable {
    func hide(imageData: Data) async throws -> EditedScreenshot
}

/// BarlessKit で解析して消す。処理はすべて端末の中で行う
nonisolated struct StatusBarHider: ScreenshotHiding {
    /// 消せなかった画像を画面に出すときの、長辺の上限（px）。
    /// カタログに無い大きさの画像はカメラの写真などで巨大なことがあるので、原寸では持たない
    static let previewMaxPixelSize = 2048

    /// 画像の展開と解析は重いので、メインスレッドの外で動かす
    @concurrent
    func hide(imageData: Data) async throws -> EditedScreenshot {
        let image = try ImageDecoder.decode(data: imageData)
        let editor = try StatusBarEditor(catalog: DeviceCatalog.bundled())
        let result = try await editor.hide(image)
        guard result.hidden != nil else {
            let preview = try ImageDecoder.decodeThumbnail(data: imageData, maxPixelSize: Self.previewMaxPixelSize)
            return EditedScreenshot(before: preview, after: preview, outcome: result.outcome)
        }
        return EditedScreenshot(before: result.original, after: result.image, outcome: result.outcome)
    }
}
