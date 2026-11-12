import BarlessTestSupport
import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarRenderer

/// docs/verification/images/ の画像を作る。どれも、時刻とアイコンのまわりだけを切り出して上から順に積んだもの
struct ReportImages {
    let catalog: DeviceCatalog
    let fixtures: [Fixture]
    let directory: URL

    private func fixture(_ name: String) throws -> Fixture {
        guard let fixture = fixtures.first(where: { $0.name == name }) else { throw ReportError("画像が見つからない: \(name)") }
        return fixture
    }

    private func write(_ rows: [Bitmap], layout: StatusBarLayout, timeTexts: [String], name: String) throws {
        let image = Montage.stack(rows.map { Montage.zones(of: $0, layout: layout, timeTexts: timeTexts) })
        try ImageEncoder.encode(image.makeCGImage()).write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// 単色: 上から「正解（元の画像）/ 消去後 / 描き直し / 正解と描き直しの差」
    func redraw(_ name: String) throws {
        let fixture = try fixture(name)
        let strip = try fixture.loadStrip()
        let background = Verification.flatBackground(of: strip, scale: fixture.scale)
        guard let (output, _) = Verification.redraw(fixture, input: strip, background: background, catalog: catalog) else {
            throw ReportError("画像を作れない（配置が決まらない）: redraw-\(name)")
        }
        let rows = [strip, output.erased, output.redrawn, ImageMetrics.heatmap(strip, output.redrawn)]
        try write(rows, layout: output.layout, timeTexts: [fixture.time], name: "redraw-\(name)")
    }

    /// 「整える」: 23:58・残量 12% の画像を消して 9:41・満タンで描き、同じ機種の 9:41 の画像（= 正解）と比べる。
    /// 上から「入力 / 整えた結果 / 正解 / 結果と正解の差」
    func tidy(input inputName: String, reference referenceName: String) throws {
        let input = try fixture(inputName)
        let reference = try fixture(referenceName).loadStrip()
        guard let output = Pipeline.run(
            try input.loadStrip(), pixelHeight: input.height, timeText: input.time, catalog: catalog, redraw: .tidy
        ) else { throw ReportError("画像を作れない（配置が決まらない）: tidy-\(inputName)") }
        let rows = [try input.loadStrip(), output.redrawn, reference, ImageMetrics.heatmap(output.redrawn, reference)]
        try write(rows, layout: output.layout, timeTexts: [input.time, "9:41"], name: "tidy-\(inputName)")
    }

    /// グラデーション: 上から「入力 / 消去後 / 元の背景 / 消去後と背景の差 / 描き直し」
    func gradient(_ name: String, kind: SyntheticBackground) throws {
        let fixture = try fixture(name)
        let strip = try fixture.loadStrip()
        let background = kind.make(width: strip.width, height: strip.height, isLight: fixture.appearance == "light")
        let input = Synthetic.transplantInk(from: strip, onto: background, scale: fixture.scale)
        guard let output = Pipeline.run(
            input, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog, redraw: fixture.spec
        ) else { throw ReportError("画像を作れない（配置が決まらない）: gradient-\(kind.rawValue)-\(name)") }
        let rows = [input, output.erased, background, ImageMetrics.heatmap(output.erased, background), output.redrawn]
        try write(rows, layout: output.layout, timeTexts: [fixture.time], name: "gradient-\(kind.rawValue)-\(name)")
    }

    /// 輪郭が横切る背景: 上から「入力 / 消去後 / 元の背景 / 消去後と背景の差」。輪郭のまわり（左右 40pt）を切り出す
    func edge(_ name: String, placement: EdgePlacement) throws {
        let fixture = try fixture(name)
        let strip = try fixture.loadStrip()
        guard let layout = fixture.expectedLayout(in: catalog) else { throw ReportError("カタログに配置が無い: \(name)") }
        let edge = placement.edge(for: layout, timeText: fixture.time)
        let background = edge.make(width: strip.width, height: strip.height, isLight: fixture.appearance == "light")
        let input = Synthetic.transplantInk(from: strip, onto: background, scale: fixture.scale)
        guard let output = Pipeline.run(input, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog) else {
            throw ReportError("画像を作れない（配置が決まらない）: edge-\(placement.rawValue)-\(name)")
        }
        let rows = [input, output.erased, background, ImageMetrics.heatmap(output.erased, background)]
        let image = Montage.stack(rows.map { Montage.window(of: $0, layout: layout, centerX: edge.throughX, halfWidthPt: 40) })
        try ImageEncoder.encode(image.makeCGImage()).write(to: directory.appendingPathComponent("edge-\(placement.rawValue)-\(name).png"))
    }

    /// 壁紙: 上から「入力 / 消去後 / 描き直し」。配置が決まらない画像は入力だけ
    func wallpaper(_ name: String) throws {
        let fixture = try fixture(name)
        let strip = try fixture.loadStrip()
        guard let layout = fixture.expectedLayout(in: catalog) else { throw ReportError("カタログに配置が無い: \(name)") }
        let output = Pipeline.run(strip, pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog, redraw: fixture.spec)
        let rows = output.map { [strip, $0.erased, $0.redrawn] } ?? [strip]
        try write(rows, layout: layout, timeTexts: [fixture.time], name: "wallpaper-\(name)")
    }
}
