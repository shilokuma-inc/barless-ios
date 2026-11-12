import BarlessTestSupport
import DeviceCatalog
import Foundation
import ImageIOKit
@testable import StatusBarAnalyzer

/// docs/verification/results.md の、消去と描き直しの節を作る
struct ReportMeasurements {
    let catalog: DeviceCatalog
    let fixtures: [Fixture]

    private var solid: [Fixture] { fixtures.filter(\.isSolidBackground) }

    // MARK: - 消去

    func eraseOnSolid() throws -> String {
        var worst = 0
        var kinds: [String: Int] = [:]
        for fixture in solid {
            let strip = try fixture.loadStrip()
            let background = Verification.flatBackground(of: strip, scale: fixture.scale)
            guard let (_, result) = Verification.erase(
                fixture, input: strip, background: background, kind: "solid", catalog: catalog
            ) else { throw ReportError("単色の背景なのに配置が決まらない: \(fixture)") }
            worst = max(worst, result.maxDifference)
            kinds[result.detected, default: 0] += 1
        }
        return Markdown.table(
            ["枚数", "背景の判定", "消した後と背景の差の最大（0〜255）"],
            [["\(solid.count)", describe(kinds), "\(worst)"]]
        )
    }

    func eraseOnGradient() throws -> String {
        let targets = try Verification.representatives(in: catalog, variants: ["light-full", "dark-full"])
        var rows: [[String]] = []
        for kind in SyntheticBackground.allCases {
            var results: [Verification.EraseResult] = []
            for fixture in targets {
                let strip = try fixture.loadStrip()
                let background = kind.make(width: strip.width, height: strip.height, isLight: fixture.appearance == "light")
                let input = Synthetic.transplantInk(from: strip, onto: background, scale: fixture.scale)
                guard let (_, result) = Verification.erase(
                    fixture, input: input, background: background, kind: kind.rawValue, catalog: catalog
                ) else { throw ReportError("\(kind.rawValue) のグラデーションで配置が決まらない: \(fixture)") }
                results.append(result)
            }
            let kinds = Dictionary(grouping: results, by: \.detected).mapValues(\.count)
            rows.append([
                Self.gradientLabels[kind] ?? kind.rawValue,
                "\(targets.count)",
                "\(results.filter(\.isLayoutCorrect).count)",
                describe(kinds),
                Markdown.number(results.map(\.meanDifference).reduce(0, +) / Double(max(1, results.count)), digits: 3),
                "\(results.map(\.maxDifference).max() ?? 0)"
            ])
        }
        return Markdown.table(["背景", "枚数", "判定が正解", "背景の判定", "差の平均（0〜255）", "差の最大（0〜255）"], rows)
    }

    /// JPEG で保存し直した画像（大きさはそのまま）での判定と消去
    func eraseOnRecompressed() throws -> String {
        var rows: [[String]] = []
        for quality in [0.9, 0.7, 0.5] {
            var results: [Verification.EraseResult] = []
            for fixture in solid {
                let strip = try fixture.loadStrip()
                let input = try Synthetic.recompressed(strip, quality: quality)
                let background = Verification.flatBackground(of: strip, scale: fixture.scale)
                if let (_, result) = Verification.erase(fixture, input: input, background: background, kind: "jpeg", catalog: catalog) {
                    results.append(result)
                }
            }
            let correct = results.filter(\.isLayoutCorrect).count
            rows.append([
                Markdown.number(quality, digits: 1),
                "\(solid.count)",
                "\(correct)",
                "\(solid.count - results.count)",
                "\(results.count - correct)",
                describe(Dictionary(grouping: results, by: \.detected).mapValues(\.count)),
                Markdown.number(results.map(\.meanDifference).reduce(0, +) / Double(max(1, results.count)), digits: 2),
                "\(results.map(\.maxDifference).max() ?? 0)"
            ])
        }
        let header = ["JPEG の品質", "枚数", "判定が正解", "決められない", "誤った配置", "背景の判定", "差の平均（0〜255）", "差の最大（0〜255）"]
        return Markdown.table(header, rows)
    }

    func wallpaper() throws -> String {
        var kinds: [String: Int] = [:]
        var decided = 0
        var keptStructure = 0
        var warned = 0
        let targets = fixtures.filter { !$0.isSolidBackground }
        for fixture in targets {
            let output = Pipeline.run(try fixture.loadStrip(), pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog)
            if let output {
                decided += 1
                if !output.analysis.backgroundInk().isEmpty { keptStructure += 1 }
                if output.analysis.mayLeaveTraces { warned += 1 }
            }
            kinds[output?.analysis.background?.rawValue ?? "（決められない）", default: 0] += 1
        }
        let header = ["枚数", "配置が決まった", "背景の判定", "背景の輪郭を拾い、消さずに残した", "跡の注意あり"]
        return Markdown.table(header, [["\(targets.count)", "\(decided)", describe(kinds), "\(keptStructure)", "\(warned)"]])
    }

    /// 斜めの輪郭が帯を横切る背景（作った背景に Simulator のインクを移した画像）
    func eraseOnEdges() throws -> String {
        let targets = try Verification.representatives(in: catalog, variants: ["light-full", "dark-full"])
        var rows: [[String]] = []
        for placement in EdgePlacement.allCases {
            var decided = 0
            var correct = 0
            var warned = 0
            var maximum = 0
            for fixture in targets {
                guard let layout = fixture.expectedLayout(in: catalog) else { throw ReportError("カタログに配置が無い: \(fixture)") }
                let strip = try fixture.loadStrip()
                let background = placement.edge(for: layout, timeText: fixture.time)
                    .make(width: strip.width, height: strip.height, isLight: fixture.appearance == "light")
                let input = Synthetic.transplantInk(from: strip, onto: background, scale: fixture.scale)
                // 電池の形で世代を決める機種は、輪郭が電池の後ろを通ると「決められない」になる
                guard let (output, result) = Verification.erase(
                    fixture, input: input, background: background, kind: placement.rawValue, catalog: catalog
                ) else { continue }
                decided += 1
                if result.isLayoutCorrect { correct += 1 }
                if output.analysis.mayLeaveTraces { warned += 1 }
                maximum = max(maximum, result.maxDifference)
            }
            rows.append([
                Self.edgeLabels[placement] ?? placement.rawValue,
                "\(targets.count)", "\(correct)", "\(targets.count - decided)", "\(decided - correct)", "\(warned)", "\(maximum)"
            ])
        }
        let header = ["輪郭が通る場所", "枚数", "判定が正解", "決められない", "誤った配置", "跡の注意あり", "差の最大（0〜255）"]
        return Markdown.table(header, rows)
    }

    // MARK: - 描き直し

    func redraw() throws -> String {
        var results: [Verification.ElementResult] = []
        for fixture in solid {
            let strip = try fixture.loadStrip()
            let background = Verification.flatBackground(of: strip, scale: fixture.scale)
            guard let (_, elements) = Verification.redraw(fixture, input: strip, background: background, catalog: catalog) else {
                throw ReportError("単色の背景なのに描き直せない: \(fixture)")
            }
            results += elements
        }
        var rows: [[String]] = []
        for element in ["time", "cellular", "wifi", "battery"] {
            for generation in OSGeneration.allCases {
                for state in ["full", "low", "real"] {
                    let group = results.filter { $0.element == element && $0.generation == generation.rawValue && $0.state == state }
                    guard !group.isEmpty else { continue }
                    let count = Double(group.count)
                    rows.append([
                        Self.elementLabels[element] ?? element, Self.generationLabels[generation] ?? generation.rawValue,
                        Self.stateLabels[state] ?? state, "\(group.count)",
                        Markdown.number(group.map(\.overlap).reduce(0, +) / count, digits: 3),
                        Markdown.number(group.map(\.overlap).min() ?? 0, digits: 3),
                        Markdown.number(group.map(\.meanDifference).reduce(0, +) / count, digits: 1),
                        "\(group.map(\.edgeDistance).max() ?? 0)",
                        Markdown.number(group.map(\.colorDifference).max() ?? 0, digits: 1)
                    ])
                }
            }
        }
        let header = [
            "要素", "iOS の世代", "中身", "枚数", "重なり（平均）", "重なり（最小）", "差の平均（0〜255）", "辺のずれの最大 (px)",
            "内側の色の差の最大（0〜255）"
        ]
        return Markdown.table(header, rows)
    }

    // MARK: - 表示用の名前

    private static let gradientLabels: [SyntheticBackground: String] = [
        .vertical: "縦のグラデーション", .horizontal: "横のグラデーション", .diagonal: "斜めのグラデーション", .radial: "円形のグラデーション"
    ]
    private static let edgeLabels: [EdgePlacement: String] = [
        .behindBattery: "電池の後ろ（斜め）", .verticalBehindBattery: "電池の後ろ（縦）", .awayFromInk: "文字もアイコンも無い所"
    ]
    private static let elementLabels = ["time": "時刻", "cellular": "電波", "wifi": "Wi-Fi", "battery": "電池"]
    private static let generationLabels: [OSGeneration: String] = [.iOS18to26: "iOS 18〜26", .iOS27: "iOS 27"]
    private static let stateLabels = ["full": "9:41・満タン", "low": "23:58・残量 12%", "real": "実機（3:16・残量 56%）"]
    private static let kindLabels = ["solid": "単色", "gradient": "グラデーション", "complex": "複雑"]

    private func describe(_ kinds: [String: Int]) -> String {
        kinds.sorted { $0.key < $1.key }.map { "\(Self.kindLabels[$0.key] ?? $0.key) \($0.value)" }.joined(separator: " / ")
    }
}
