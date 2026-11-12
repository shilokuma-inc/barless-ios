import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarEditor
import StatusBarRenderer
import Testing

/// 透かし: 画像の右下に、小さくアプリ名を載せる
struct WatermarkTests {
    /// 2 枚の画像で、色が違う画素
    private func changedPixels(_ lhs: Bitmap, _ rhs: Bitmap) -> [(x: Int, y: Int)] {
        var result: [(x: Int, y: Int)] = []
        for y in 0..<lhs.height {
            for x in 0..<lhs.width where lhs[x, y] != rhs[x, y] {
                result.append((x, y))
            }
        }
        return result
    }

    /// 右下の隅に、小さく入る。文字のある範囲の外は 1 画素も変えない
    @Test(arguments: ["キレスク", "Barless"])
    func drawsSmallTextInBottomRightCorner(text: String) throws {
        let original = Bitmap(width: 1206, height: 2622, fill: RGB(red: 246, green: 246, blue: 248))
        var bitmap = original

        try WatermarkRenderer().draw(text, into: &bitmap)

        let frame = try #require(WatermarkRenderer().frame(of: text, width: 1206, height: 2622))
        let changed = changedPixels(original, bitmap)
        #expect(changed.count > 200)
        #expect(changed.allSatisfy { frame.contains(x: $0.x, y: $0.y) })
        // 右端と下端から、幅の 4% ほど内側。幅は画像の 3 割より狭く、高さは幅の 4% より低い
        #expect(frame.maxX <= 1206 - 40 && frame.maxX >= 1206 - 60)
        #expect(frame.maxY <= 2622 - 40 && frame.maxY >= 2622 - 70)
        #expect(frame.width < 1206 * 3 / 10 && frame.height < 50)
        // 明るい画像には、暗い半透明の文字
        #expect(changed.allSatisfy { bitmap[$0.x, $0.y].luma < original[$0.x, $0.y].luma })
        #expect(changed.allSatisfy { bitmap[$0.x, $0.y].luma > 90 })
    }

    /// 暗い画像には、明るい文字
    @Test
    func usesLightTextOnDarkBackground() throws {
        let original = Bitmap(width: 1206, height: 2622, fill: RGB(red: 20, green: 24, blue: 40))
        var bitmap = original

        try WatermarkRenderer().draw("Barless", into: &bitmap)

        let changed = changedPixels(original, bitmap)
        #expect(changed.count > 200)
        #expect(changed.allSatisfy { bitmap[$0.x, $0.y].luma > original[$0.x, $0.y].luma })
    }

    /// 文字が空のとき・画像が小さすぎて入らないときは、何もしない
    @Test
    func drawsNothingWhenThereIsNoRoom() throws {
        let original = Bitmap(width: 1206, height: 2622, fill: .white)
        var bitmap = original
        try WatermarkRenderer().draw("", into: &bitmap)
        #expect(bitmap.data == original.data)
        #expect(WatermarkRenderer().frame(of: "", width: 1206, height: 2622) == nil)

        let tiny = Bitmap(width: 40, height: 3, fill: .white)
        var drawn = tiny
        try WatermarkRenderer().draw("Barless", into: &drawn)
        #expect(drawn.data == tiny.data)
    }
}

/// 自由に決めた値を含むか（透かしを入れるかどうかの判定）
struct PlaySpecCustomizationTests {
    @Test
    func standardAndKeptOrHiddenValuesAreNotCustomized() {
        #expect(!PlaySpec.standard.isCustomized)
        #expect(!PlaySpec(time: .keep, cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: 1)).isCustomized)
        #expect(!PlaySpec(time: .hide, cellularBars: nil, wifiBars: nil, battery: nil).isCustomized)
    }

    @Test(arguments: [
        PlaySpec(time: .set("12:25"), cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: 1)),
        PlaySpec(time: .set("9:41"), cellularBars: 2, wifiBars: 3, battery: BatterySpec(level: 1)),
        PlaySpec(time: .set("9:41"), cellularBars: 4, wifiBars: 1, battery: BatterySpec(level: 1)),
        PlaySpec(time: .set("9:41"), cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: 0.8)),
        PlaySpec(time: .keep, cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: 1, state: .charging)),
        PlaySpec(time: .hide, cellularBars: 0, wifiBars: nil, battery: nil)
    ])
    func anyFreeValueIsCustomized(spec: PlaySpec) {
        #expect(spec.isCustomized)
    }
}
