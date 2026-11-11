import DeviceCatalog
import ImageIOKit
import InpaintEngine
import StatusBarAnalyzer
import StatusBarRenderer

/// 解析 → 消去 → 描き直しを通す（アプリのエディタが行う処理と同じ流れ）
enum Pipeline {
    struct Output {
        let analysis: StatusBarAnalysis
        let layout: StatusBarLayout
        /// ステータスバーを消した画像
        let erased: Bitmap
        /// 消した上に描き直した画像（`spec` を渡さなければ `erased` と同じ）
        let redrawn: Bitmap
    }

    /// - Parameter timeText: 画像に写っている時刻（文字認識の結果の代わりに渡す）
    static func run(
        _ input: Bitmap,
        pixelHeight: Int,
        timeText: String?,
        catalog: DeviceCatalog,
        redraw spec: StatusBarSpec? = nil
    ) -> Output? {
        let analysis = StatusBarAnalyzer.analyze(strip: input, pixelHeight: pixelHeight, timeText: timeText, catalog: catalog)
        guard let layout = analysis.decision.layout, let mask = analysis.eraseMask(), let appearance = analysis.appearance else {
            return nil
        }
        // 単色なら 1 色で塗り、それ以外は周りから補間する
        let erased = analysis.background == .solid
            ? SolidFillInpainter().fill(input, mask: mask)
            : GradientInpainter().fill(input, mask: mask)
        var redrawn = erased
        if let spec {
            try? StatusBarRenderer().render(spec, layout: layout, appearance: appearance, into: &redrawn)
        }
        return Output(analysis: analysis, layout: layout, erased: erased, redrawn: redrawn)
    }
}
