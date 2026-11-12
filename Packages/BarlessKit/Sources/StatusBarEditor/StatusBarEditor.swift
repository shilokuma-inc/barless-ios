import CoreGraphics
import DeviceCatalog
import ImageIOKit
import InpaintEngine
import StatusBarAnalyzer
import StatusBarRenderer

/// スクリーンショット 1 枚に対する編集の入口。解析 → 消去 → 描き直しをまとめて行う（仕様書 §5-1）。
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

    /// ステータスバーを編集する。次の 2 つを 1 回の解析で作る。
    ///
    /// - 「隠す」: 文字とアイコンを、背景になじませて消す（「埋める」）
    /// - 「整える」: 消したうえで、`tidy` の中身（既定は 9:41・電波 4 本・Wi-Fi 最大・電池満タン）を自作のベクターで描き直す
    ///
    /// 機種を決められないときは、誤った位置を消さずに元の画像のまま返す（`HideOutcome.notHidden`）。
    /// 背景が写真・模様のときと、輪郭が文字・アイコンの後ろを通っているときも消すが、
    /// 跡が残ることがあるので `HiddenStatusBar.mayLeaveTraces` で分かるようにしている。
    public func edit(_ image: CGImage, tidy spec: StatusBarSpec = .tidy) async throws -> EditResult {
        let analysis = try await analyzer.analyze(image)
        guard let layout = analysis.decision.layout else {
            return EditResult(original: image, hidden: image, tidied: nil, outcome: .notHidden(Self.failure(for: analysis.decision)))
        }
        guard let mask = analysis.eraseMask(), !mask.isEmpty,
              let background = analysis.background, let appearance = analysis.appearance else {
            return EditResult(original: image, hidden: image, tidied: nil, outcome: .notHidden(.undetermined))
        }
        // 単色なら 1 色で塗り、それ以外は周りから補間する
        let inpainter: any Inpainter = background == .solid ? SolidFillInpainter() : GradientInpainter()
        let source = try Bitmap(cgImage: image)
        let erased = try await inpainter.inpaint(source, mask: mask)

        // 「整える」: キャリア名のある機種では、キャリア名を残して消し直してから描く
        let plan = analysis.tidyPlan() ?? .plain
        var tidied = erased
        if !plan.kept.isEmpty, let tidyMask = analysis.eraseMask(keeping: plan.kept) {
            tidied = try await inpainter.inpaint(source, mask: tidyMask)
        }
        var content = spec
        if !plan.drawsWiFi { content.wifiBars = nil }
        try StatusBarRenderer().render(content, layout: layout, appearance: appearance, into: &tidied, wifiShiftX: plan.wifiShiftX)

        let statusBar = HiddenStatusBar(
            layout: layout,
            background: background,
            bandHeight: Self.bandHeight(of: layout, in: image),
            mayLeaveTraces: analysis.mayLeaveTraces
        )
        return EditResult(
            original: image, hidden: try erased.makeCGImage(), tidied: try tidied.makeCGImage(), outcome: .hidden(statusBar)
        )
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
