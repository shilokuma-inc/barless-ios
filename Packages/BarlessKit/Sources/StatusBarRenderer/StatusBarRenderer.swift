import CoreGraphics
import DeviceCatalog
import ImageIOKit

/// ステータスバーを描く。
///
/// 時刻はシステムフォントの輪郭、電波・Wi-Fi・電池は自作のベクター（SF Symbols は使わない。仕様書 §5-3）。
/// 位置と大きさは `DeviceCatalog` の実測に合わせるので、機種・iOS の世代ごとの見た目になる。
/// 背景は描かない。先に `InpaintEngine` で元の表示を消した画像に重ねる。
public struct StatusBarRenderer: Sendable {
    public init() {}

    /// - Parameters:
    ///   - spec: 描く中身。`nil` の要素は描かない
    ///   - layout: 判定した配置
    ///   - appearance: 文字とアイコンの色（黒か白）
    ///   - bitmap: 描き込む画像。スクリーンショット全体でも、上端だけを切り出したものでもよい（座標は左上が原点の px）
    ///   - wifiShiftX: Wi-Fi を、配置の位置から右へずらす量（px）。キャリア名の右に Wi-Fi が並ぶ機種で、
    ///     キャリア名の長さに合わせるのに使う（配置の実測は、Simulator のキャリア名の長さでの位置）
    public func render(
        _ spec: StatusBarSpec,
        layout: StatusBarLayout,
        appearance: ContentAppearance,
        into bitmap: inout Bitmap,
        wifiShiftX: Int = 0
    ) throws {
        let palette = Palette(appearance: appearance, generation: layout.generation)
        try bitmap.draw { context in
            context.setShouldAntialias(true)
            if let time = spec.time {
                context.addPath(TimeTypography(layout: layout).path(for: time))
                context.setFillColor(palette.content())
                context.fillPath()
            }
            if let bars = spec.cellularBars {
                CellularIcon(layout: layout).draw(activeBars: bars, palette: palette, in: context)
            }
            if let bars = spec.wifiBars {
                context.saveGState()
                context.translateBy(x: CGFloat(wifiShiftX), y: 0)
                WiFiIcon(layout: layout).draw(activeBars: bars, palette: palette, in: context)
                context.restoreGState()
            }
            if let battery = spec.battery {
                BatteryIcon(layout: layout).draw(battery, palette: palette, in: context)
            }
        }
    }
}
