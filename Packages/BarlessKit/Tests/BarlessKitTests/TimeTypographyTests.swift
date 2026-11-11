import DeviceCatalog
import StatusBarRenderer
import Testing

/// 時刻の組み方（フォントの大きさと位置）が、実測と合うこと
struct TimeTypographyTests {
    /// 実測の文字列（9:41 など）を組むと、実測の矩形と 4 辺とも 1px 以内で合う
    @Test
    func reproducesMeasuredSample() throws {
        for layout in try DeviceCatalog.bundled().layouts {
            let sample = try #require(layout.timeSamples.first)
            let predicted = TimeTypography(layout: layout).inkRect(for: sample.text)
            #expect(predicted.maxEdgeDistance(to: sample.ink) <= 1, "\(layout.id): 見込み \(predicted) 実測 \(sample.ink)")
        }
    }

    /// 時刻は中央ぞろえ。9:41 から求めた大きさと中心で 23:58 を組むと、実測の 23:58 と 4 辺とも 2px 以内で合う
    @Test
    func predictsAnotherTimeByCenterAlignment() throws {
        let layouts = try DeviceCatalog.bundled().layouts.filter { $0.timeSamples.count >= 2 }
        #expect(layouts.count == 24)
        for layout in layouts {
            let other = layout.timeSamples[1]
            let predicted = TimeTypography(layout: layout).inkRect(for: other.text)
            #expect(predicted.maxEdgeDistance(to: other.ink) <= 2, "\(layout.id): 見込み \(predicted) 実測 \(other.ink)")
        }
    }

    /// 桁が増えても中心は動かない
    @Test
    func keepsCenterForLongerText() throws {
        let layout = try #require(try DeviceCatalog.bundled().layout(id: "1179x2556-a/ios27"))
        let typography = TimeTypography(layout: layout)
        let short = typography.inkRect(for: "1:11")
        let long = typography.inkRect(for: "20:08")
        #expect(long.width > short.width)
        #expect(abs(short.midX - long.midX) <= 3)
        #expect(short.y == long.y || abs(short.y - long.y) <= 1)
    }
}
