import CoreGraphics
import DeviceCatalog
import ImageIOKit
import InpaintEngine
import StatusBarAnalyzer

/// スクリーンショット 1 枚に対する編集の入口。解析 → 消去をまとめて行う（仕様書 §5-1）。
///
/// アプリの画面・共有シート拡張・ショートカットから同じものを呼ぶ。処理はすべて端末の中で行う。
public struct StatusBarEditor: Sendable {
    private let catalog: DeviceCatalog
    private let analyzer: StatusBarAnalyzer

    public init(catalog: DeviceCatalog, recognizer: any TimeTextRecognizing = VisionTimeTextRecognizer()) {
        self.catalog = catalog
        self.analyzer = StatusBarAnalyzer(catalog: catalog, recognizer: recognizer)
    }

    /// 大きさ（px）だけで「消せない」と分かるなら、その理由を返す。
    ///
    /// 画素を展開する前に呼べば、カメラの写真のような巨大な画像を、原寸で持たずに済む
    public func failureKnownFromSize(pixelWidth: Int, pixelHeight: Int) -> HideFailure? {
        guard catalog.candidates(pixelWidth: pixelWidth, pixelHeight: pixelHeight).isEmpty else { return nil }
        return catalog.unsupportedScreen(pixelWidth: pixelWidth, pixelHeight: pixelHeight) == nil ? .unknownSize : .unsupportedScreen
    }

    /// ステータスバーの文字とアイコンを、背景になじませて消す（「隠す」の「埋める」）。
    ///
    /// 機種を決められないときは、誤った位置を消さずに元の画像のまま返す（`HideOutcome.notHidden`）。
    /// 背景が写真・模様のときも消すが、跡が残ることがあるので `HiddenStatusBar.mayLeaveTraces` で分かるようにしている。
    public func hide(_ image: CGImage) async throws -> HideResult {
        let analysis = try await analyzer.analyze(image)
        guard let layout = analysis.decision.layout else {
            return HideResult(original: image, image: image, outcome: .notHidden(Self.failure(for: analysis.decision)))
        }
        guard let mask = analysis.eraseMask(), !mask.isEmpty, let background = analysis.background else {
            return HideResult(original: image, image: image, outcome: .notHidden(.undetermined))
        }
        // 単色なら 1 色で塗り、それ以外は周りから補間する
        let inpainter: any Inpainter = background == .solid ? SolidFillInpainter() : GradientInpainter()
        let erased = try await inpainter.inpaint(image, mask: mask)
        let hidden = HiddenStatusBar(layout: layout, background: background, bandHeight: Self.bandHeight(of: layout, in: image))
        return HideResult(original: image, image: erased, outcome: .hidden(hidden))
    }

    private static func failure(for decision: LayoutDecision) -> HideFailure {
        switch decision {
        case .unknownSize: .unknownSize
        case .unsupported: .unsupportedScreen
        case .ambiguous, .resolved: .undetermined
        }
    }

    /// ステータスバーの帯の高さ。文字とアイコンは帯の上下の中央にあるので、インクの上端と下端の位置を足すと帯の高さになる
    static func bandHeight(of layout: StatusBarLayout, in image: CGImage) -> Int {
        min(image.height, layout.inkTop + layout.inkBottom)
    }
}
