import CoreGraphics
import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarRenderer

/// 撮影モードとテストで使う、作り物のスクリーンショット（iPhone 17・iOS 27 の大きさ）。
///
/// 写真を同梱しないで済むように、一覧の画面に見立てた絵をその場で描く。ステータスバーは BarlessKit で描くので、
/// 本物と同じ位置と形になり、アプリの解析がそのまま通る
nonisolated enum SampleScreenshot {
    /// 描くステータスバーの配置
    static let layoutID = "1206x2622-a/ios27"
    /// 描く時刻
    static let time = "2:47"

    static func pngData() throws -> Data {
        let catalog = try DeviceCatalog.bundled()
        guard let layout = catalog.layout(id: layoutID) else { throw DeviceCatalogError.resourceNotFound }
        var bitmap = Bitmap(width: layout.pixelWidth, height: layout.pixelHeight, fill: RGB(red: 246, green: 246, blue: 248))
        let scale = CGFloat(layout.scale)
        let width = CGFloat(layout.pixelWidth)
        try bitmap.draw { context in
            // 見出しに見立てた太い線
            fill(CGRect(x: 20, y: 84, width: 150, height: 30), radius: 15, gray: 0.1, scale: scale, in: context)
            // 一覧の行に見立てた、白い角丸の四角と 2 本の線
            for row in 0..<7 {
                let card = CGRect(x: 16, y: 140 + CGFloat(row) * 92, width: width / scale - 32, height: 80)
                fill(card, radius: 16, gray: 1, scale: scale, in: context)
                let title = CGRect(x: 32, y: card.minY + 20, width: 120 + CGFloat(row % 3) * 40, height: 14)
                fill(title, radius: 7, gray: 0.78, scale: scale, in: context)
                let detail = CGRect(x: 32, y: card.minY + 46, width: 210 - CGFloat(row % 2) * 50, height: 12)
                fill(detail, radius: 6, gray: 0.88, scale: scale, in: context)
            }
        }
        // 「隠したくなる」表示にしておく（半端な時刻・電波 1 本・電池 12%）
        let spec = StatusBarSpec(time: time, cellularBars: 1, wifiBars: 1, battery: BatterySpec(level: 0.12))
        try StatusBarRenderer().render(spec, layout: layout, appearance: .darkContent, into: &bitmap)
        return try ImageEncoder.encode(bitmap.makeCGImage())
    }

    /// SNS などで保存し直して、大きさが変わった画像に見立てたもの（幅 900px に縮める）。
    /// 対応している機種のどれとも大きさが合わないので、自動では消せず、手動調整に進む
    static func resavedPNGData() throws -> Data {
        let original = try ImageDecoder.decode(data: pngData())
        let width = 900
        let height = Int((Double(original.height) * Double(width) / Double(original.width)).rounded())
        var bitmap = Bitmap(width: width, height: height, colorSpace: original.colorSpace)
        try bitmap.draw { context in
            // `draw` の座標は下向きが正なので、画像が逆さにならないように、上下を戻してから描く
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try ImageEncoder.encode(bitmap.makeCGImage())
    }

    /// 角丸の四角をグレーで塗る。`rect` と `radius` は pt で渡す
    private static func fill(_ rect: CGRect, radius: CGFloat, gray: CGFloat, scale: CGFloat, in context: CGContext) {
        let scaled = rect.applying(CGAffineTransform(scaleX: scale, y: scale))
        context.setFillColor(gray: gray, alpha: 1)
        context.addPath(CGPath(roundedRect: scaled, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil))
        context.fillPath()
    }
}
