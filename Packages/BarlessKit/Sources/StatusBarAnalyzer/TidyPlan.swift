import DeviceCatalog
import ImageIOKit
import StatusBarRenderer

/// 「整える」で描き直すときの、画像ごとの合わせ方
public struct TidyPlan: Sendable, Equatable {
    /// 消さずに残す範囲（px）。キャリア名が入る
    public let kept: [PixelRect]
    /// Wi-Fi を、配置の位置から右へずらす量（px）
    public let wifiShiftX: Int
    /// Wi-Fi を描く場所があるか。キャリア名が長くて時刻との間に入らないときは `false`
    public let drawsWiFi: Bool

    /// 配置のとおりに描く（何も残さず、どこもずらさない）
    public static let plain = TidyPlan(kept: [], wifiShiftX: 0, drawsWiFi: true)
}

extension StatusBarAnalysis {
    /// 「整える」での合わせ方。配置が決まっていなければ `nil`。
    ///
    /// ホームボタンの機種は、左に「電波・キャリア名・Wi-Fi」が並び、Wi-Fi の位置がキャリア名の長さで変わる
    /// （配置の実測は Simulator の「Carrier」での位置）。キャリア名は「整える」の対象ではないので残し、
    /// Wi-Fi は、キャリア名のすぐ右に描く
    public func tidyPlan() -> TidyPlan? {
        guard let scan, case let .resolved(match, _) = decision else { return nil }
        let layout = match.layout
        guard layout.style == .centeredTime, let carrier = layout.carrier else { return .plain }
        let scale = layout.scale
        let timeLeft = (match.timeBlob ?? TimeTypography(layout: layout).inkRect(for: timeText ?? "9:41")).x
        // 電波の右から時刻の左までにあるインク。電波とつながって拾われていても、電波の右端で切る
        let start = layout.cellular.maxX + scale
        let parts = scan.blobs.compactMap { blob -> PixelRect? in
            guard blob.maxX <= timeLeft - 2 * scale, blob.maxX > start else { return nil }
            let left = max(blob.x, start)
            return PixelRect(x: left, y: blob.y, width: blob.maxX - left, height: blob.height)
        }
        guard let last = parts.last else { return .plain }
        // いちばん右のかたまりが Wi-Fi ほどの幅なら、Wi-Fi か、5G などの表示。それは消して、残りをキャリア名として残す
        let isIndicator = parts.count >= 2 && last.width <= layout.wifi.width + Self.indicatorSlackPt * scale
        let kept = isIndicator ? Array(parts.dropLast()) : parts
        guard let carrierRight = kept.last?.maxX else { return .plain }
        // Wi-Fi は、キャリア名の右端から、実測と同じすき間を空けて置く。
        // 元の Wi-Fi の位置を使わないのは、薄い Wi-Fi（0 本）は縁が拾えず、位置が 1px ほどずれるため
        let wifiLeft = carrierRight + (layout.wifi.x - carrier.maxX)
        let fits = wifiLeft + layout.wifi.width <= timeLeft - 2 * scale
        return TidyPlan(kept: kept, wifiShiftX: fits ? wifiLeft - layout.wifi.x : 0, drawsWiFi: fits)
    }

    /// Wi-Fi の代わりに出る表示（5G・LTE など）とみなす幅の、Wi-Fi の幅からの余裕（pt）
    static let indicatorSlackPt = 8

    /// 消去に使うマスクから、`kept` の範囲を外したもの。範囲の中のインクは消さない
    public func eraseMask(keeping kept: [PixelRect]) -> PixelMask? {
        guard let scan, let layout = decision.layout, var mask = eraseMask() else { return nil }
        guard !kept.isEmpty else { return mask }
        // 残す範囲のインクから広がった分（縁の 1pt）も外す。範囲の外のインクから範囲に入り込んだ分は、範囲の中だけ外す
        var keptInk = PixelMask(originX: scan.mask.originX, originY: scan.mask.originY, width: scan.mask.width, height: scan.mask.height)
        for rect in kept {
            for y in rect.y..<rect.maxY {
                for x in rect.x..<rect.maxX {
                    if scan.mask[x, y] { keptInk[x, y] = true }
                    mask[x, y] = false
                }
            }
        }
        let halo = keptInk.dilated(by: layout.scale)
        var others = scan.mask
        for y in keptInk.originY..<(keptInk.originY + keptInk.height) {
            for x in keptInk.originX..<(keptInk.originX + keptInk.width) where keptInk[x, y] {
                others[x, y] = false
            }
        }
        let othersHalo = others.dilated(by: layout.scale)
        for y in halo.originY..<(halo.originY + halo.height) {
            for x in halo.originX..<(halo.originX + halo.width) where halo[x, y] && !othersHalo[x, y] {
                mask[x, y] = false
            }
        }
        return mask
    }
}
