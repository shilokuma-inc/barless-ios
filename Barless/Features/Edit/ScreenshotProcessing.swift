import CoreGraphics
import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarEditor

/// 画面に出す 1 枚分の結果
nonisolated struct EditedScreenshot: Sendable {
    /// 元の画像（見比べる用）
    let before: CGImage
    /// 「隠す」: ステータスバーを消した画像。消せなかったときは `before` と同じ
    let after: CGImage
    /// 「整える」: 消したうえで、定番の表示に描き直した画像。消せなかったときは `nil`
    let tidied: CGImage?
    let outcome: HideOutcome

    /// 消せたときの情報
    var hidden: HiddenStatusBar? {
        if case let .hidden(hidden) = outcome { return hidden }
        return nil
    }
}

/// 選んだ画像のステータスバーを編集する処理（「隠す」と「整える」の両方の画像を作る）。画面のテストで差し替えられるようにしている
nonisolated protocol ScreenshotProcessing: Sendable {
    func process(imageData: Data) async throws -> EditedScreenshot
}

/// BarlessKit で解析して、消した画像と描き直した画像を作る。処理はすべて端末の中で行う
nonisolated struct ScreenshotProcessor: ScreenshotProcessing {
    /// 消せなかった画像を画面に出すときの、長辺の上限（px）
    static let previewMaxPixelSize = 2048

    /// 画像の展開と解析は重いので、メインスレッドの外で動かす
    @concurrent
    func process(imageData: Data) async throws -> EditedScreenshot {
        let editor = try StatusBarEditor(catalog: DeviceCatalog.bundled())
        // 対応している機種のどれとも大きさが合わない画像は、カメラの写真のように巨大なことがある。
        // 大きさは画素を展開しなくても読めるので、先に確かめて、原寸では展開しない
        if let size = ImageDecoder.pixelSize(of: imageData),
           let failure = editor.failureKnownFromSize(pixelWidth: size.width, pixelHeight: size.height) {
            return try preview(of: imageData, outcome: .notHidden(failure))
        }
        let result = try await editor.edit(ImageDecoder.decode(data: imageData))
        guard result.statusBar != nil else {
            return try preview(of: imageData, outcome: result.outcome)
        }
        return EditedScreenshot(before: result.original, after: result.hidden, tidied: result.tidied, outcome: result.outcome)
    }

    /// 消せなかった画像の結果。画面に出すだけなので、縮めた画像を持つ
    private func preview(of imageData: Data, outcome: HideOutcome) throws -> EditedScreenshot {
        let preview = try ImageDecoder.decodeThumbnail(data: imageData, maxPixelSize: Self.previewMaxPixelSize)
        return EditedScreenshot(before: preview, after: preview, tidied: nil, outcome: outcome)
    }
}
