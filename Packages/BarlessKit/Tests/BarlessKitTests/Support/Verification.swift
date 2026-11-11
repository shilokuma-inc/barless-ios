import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import StatusBarRenderer

/// 検証 2 で 1 枚の画像から取る数値（docs/verification.md）
enum Verification {
    /// 描き直した要素 1 つと、正解の画像との比較
    struct ElementResult: Codable {
        let fixture: String
        let layout: String
        let generation: String
        /// `full`（9:41・満タン）/ `low`（23:58・残量 12%）/ `real`（実機）
        let state: String
        /// `time` / `cellular` / `wifi` / `battery`
        let element: String
        /// インクの重なり（1 で完全に一致）
        let overlap: Double
        /// 画素・チャンネルあたりの差の平均（0〜255）
        let meanDifference: Double
        /// インクの範囲の 4 辺の差の最大（px）
        let edgeDistance: Int
        /// インクの色の差（輪郭を除いた内側の画素での、チャンネルあたりの差の平均。0〜255）
        let colorDifference: Double
    }

    /// 消した結果と、インクが無い背景との比較
    struct EraseResult: Codable {
        let fixture: String
        /// `solid` / `vertical` / `horizontal` / `diagonal` / `radial` / `wallpaper`
        let background: String
        /// 解析が判定した背景の種類
        let detected: String
        let meanDifference: Double
        let maxDifference: Int
        /// 見て分かる差がある画素の割合
        let visibleRatio: Double
        let isLayoutCorrect: Bool
    }

    /// 比較する範囲: 帯の上下 3pt まで、左右は画面の端 4pt を除く
    static func band(of layout: StatusBarLayout) -> PixelRect {
        let margin = 4 * layout.scale
        return PixelRect(
            x: margin,
            y: max(0, layout.inkTop - 3 * layout.scale),
            width: layout.pixelWidth - 2 * margin,
            height: layout.inkBottom - layout.inkTop + 6 * layout.scale
        )
    }

    /// 要素ごとの、正解でインクが載っている範囲（時刻は写っている文字列で計算する）
    static func elementRects(of layout: StatusBarLayout, timeText: String) -> [(name: String, rect: PixelRect)] {
        [
            ("time", TimeTypography(layout: layout).inkRect(for: timeText)),
            ("cellular", layout.cellular),
            ("wifi", layout.wifi),
            ("battery", layout.battery)
        ]
    }

    static func state(of fixture: Fixture) -> String {
        if fixture.source == "device" { return "real" }
        return fixture.variant.hasSuffix("low") ? "low" : "full"
    }

    /// 消して、同じ中身で描き直し、元の画像（= 正解）と要素ごとに比べる
    static func redraw(
        _ fixture: Fixture,
        input: Bitmap,
        background: Bitmap,
        catalog: DeviceCatalog
    ) -> (Pipeline.Output, [ElementResult])? {
        guard let output = Pipeline.run(
            input, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog, redraw: fixture.spec
        ) else { return nil }
        let layout = output.layout
        let results = elementRects(of: layout, timeText: fixture.time).compactMap { element -> ElementResult? in
            let area = element.rect.insetBy(dx: -2 * layout.scale, dy: -2 * layout.scale)
            // 撮影の揺れで、正解の画像に要素が写っていないことがある（iPhone 12・iOS 26.5 の Wi-Fi）。その要素は比べない
            guard let truthBounds = ImageMetrics.inkBounds(input, background: background, in: area) else { return nil }
            let drawnBounds = ImageMetrics.inkBounds(output.redrawn, background: background, in: area)
            return ElementResult(
                fixture: fixture.name,
                layout: layout.id,
                generation: layout.generation.rawValue,
                state: state(of: fixture),
                element: element.name,
                overlap: ImageMetrics.inkOverlap(truth: input, rendered: output.redrawn, background: background, in: area),
                meanDifference: ImageMetrics.difference(input, output.redrawn, in: area).meanAbsolute,
                edgeDistance: drawnBounds.map { $0.maxEdgeDistance(to: truthBounds) } ?? .max,
                colorDifference: ImageMetrics.inkColorDifference(
                    truth: input, rendered: output.redrawn, background: background, in: area
                ) ?? 0
            )
        }
        return (output, results)
    }

    /// 消した結果を、インクが無い背景と比べる
    static func erase(
        _ fixture: Fixture,
        input: Bitmap,
        background: Bitmap,
        kind: String,
        catalog: DeviceCatalog
    ) -> (Pipeline.Output, EraseResult)? {
        guard let output = Pipeline.run(input, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog) else { return nil }
        let difference = ImageMetrics.difference(output.erased, background, in: band(of: output.layout))
        let result = EraseResult(
            fixture: fixture.name,
            background: kind,
            detected: output.analysis.background?.rawValue ?? "-",
            meanDifference: difference.meanAbsolute,
            maxDifference: difference.maxAbsolute,
            visibleRatio: difference.visibleRatio,
            isLayoutCorrect: output.layout.id == fixture.expectedLayout(in: catalog)?.id
        )
        return (output, result)
    }

    /// 配置ごとに 1 機種（カタログの実測の元の先頭）を選んだ、Simulator の画像
    static func representatives(in catalog: DeviceCatalog, variants: Set<String>) throws -> [Fixture] {
        let sources = Set(catalog.layouts.compactMap(\.sources.first))
        return try Fixtures.supported().filter { fixture in
            fixture.source == "simulator" && variants.contains(fixture.variant) && sources.contains("\(fixture.device)__\(fixture.runtime)")
        }
    }

    /// 単色の背景の画像について、インクが無い背景（1 色で塗った画像）を作る
    static func flatBackground(of strip: Bitmap, scale: Int) -> Bitmap {
        Bitmap(width: strip.width, height: strip.height, fill: strip[strip.width / 2, 4 * scale], colorSpace: strip.colorSpace)
    }
}
