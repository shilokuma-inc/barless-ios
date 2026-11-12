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
    /// 「整える」: 消したうえで、定番の表示に描き直した画像。消せなかったとき・手動調整の結果では `nil`
    let tidied: CGImage?
    /// 自動の判定の結果
    let outcome: HideOutcome
    /// 自動で消せなかった画像で、手動調整へ進めるなら、その元のデータ
    var manualSource: ManualSource?
    /// 手動調整の結果なら、その中身（`after` が、帯を手動で合わせて消した画像）
    var manual: ManualEdit?

    /// 自動で消せたときの情報
    var hidden: HiddenStatusBar? {
        if case let .hidden(hidden) = outcome { return hidden }
        return nil
    }

    /// 保存できる結果があるか（自動で消せた、または手動で調整した）
    var hasResult: Bool {
        hidden != nil || manual != nil
    }

    /// 消した帯の高さ（px。画像の上端から）。結果が無ければ `nil`
    var bandHeight: Int? {
        manual?.adjustment.bandHeight ?? hidden?.bandHeight
    }
}

/// 手動調整に使う、元の画像のデータ。調整の画面を開いたときに、元の大きさで読み直す
/// （消せなかった画像は、画面に出す用に縮めたものしか持っていないため）
nonisolated struct ManualSource: Sendable {
    let imageData: Data
}

/// 手動調整の結果に添える情報
nonisolated struct ManualEdit: Sendable, Equatable {
    let adjustment: ManualAdjustment
    /// 消した跡が残りそうか
    let mayLeaveTraces: Bool
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

    /// 消せなかった画像の結果。画面に出すだけなので、縮めた画像を持つ。
    /// 手動調整で扱える大きさなら、そのために元のデータも持たせる（カメラの写真のような巨大な画像は対象外）
    private func preview(of imageData: Data, outcome: HideOutcome) throws -> EditedScreenshot {
        let preview = try ImageDecoder.decodeThumbnail(data: imageData, maxPixelSize: Self.previewMaxPixelSize)
        let canAdjust = ImageDecoder.pixelSize(of: imageData).map {
            ManualEditor.supports(pixelWidth: $0.width, pixelHeight: $0.height)
        } ?? false
        let source = canAdjust ? ManualSource(imageData: imageData) : nil
        return EditedScreenshot(before: preview, after: preview, tidied: nil, outcome: outcome, manualSource: source)
    }
}
