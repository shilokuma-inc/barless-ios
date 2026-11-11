import BarlessTestSupport
import DeviceCatalog
import Foundation
import ImageIOKit
import StatusBarAnalyzer
import StatusBarRenderer

/// docs/verification/results.md の各節（数値の表）を作る
struct ReportSections {
    let catalog: DeviceCatalog
    let fixtures: [Fixture]

    private static let variantLabels: [(variant: String, label: String)] = [
        ("light-full", "設定アプリ・ライト・9:41"),
        ("light-low", "設定アプリ・ライト・23:58"),
        ("dark-full", "設定アプリ・ダーク・9:41"),
        ("dark-home", "ホーム画面（壁紙）・9:41"),
        ("light-real", "実機（iPhone 16 Pro Max・iOS 27.2）・ライト"),
        ("dark-real", "実機（iPhone 16 Pro Max・iOS 27.2）・ダーク")
    ]

    // MARK: - 判定

    func decision() throws -> String {
        var rows: [[String]] = []
        var margins: [Double] = []
        var evidences: [String: Int] = [:]
        for (variant, label) in Self.variantLabels {
            var counts = (total: 0, withText: 0, withoutText: 0, undecided: 0, wrong: 0)
            for fixture in fixtures where fixture.variant == variant {
                let strip = try fixture.loadStrip()
                let expected = fixture.expectedLayout(in: catalog)?.id
                let known = analyze(strip, fixture, timeText: fixture.time)
                let blind = analyze(strip, fixture, timeText: nil)
                counts.total += 1
                if known.decision.layout?.id == expected { counts.withText += 1 }
                if blind.decision.layout?.id == expected { counts.withoutText += 1 }
                if known.decision.layout == nil {
                    counts.undecided += 1
                } else if known.decision.layout?.id != expected {
                    counts.wrong += 1
                }
                if case let .resolved(_, evidence) = known.decision {
                    evidences[evidence.rawValue, default: 0] += 1
                    if evidence == .time, known.candidates.count >= 2 {
                        margins.append(known.candidates[1].timeError - known.candidates[0].timeError)
                    }
                }
            }
            rows.append([label, "\(counts.total)", "\(counts.withText)", "\(counts.withoutText)", "\(counts.undecided)", "\(counts.wrong)"])
        }
        let header = ["画像", "枚数", "正解（時刻の文字列あり）", "正解（文字列なし）", "決められない", "誤った配置"]
        let evidenceRows = evidences.sorted { $0.key < $1.key }.map { [$0.key, "\($0.value)"] }
        return Markdown.table(header, rows)
            + "\n決め手（時刻の文字列ありのとき）:\n\n" + Markdown.table(["決め手", "枚数"], evidenceRows)
            + "\n時刻で決まった \(margins.count) 枚の、1 位と 2 位の候補の「時刻のずれ」の差: "
            + "最小 \(Markdown.number(margins.min() ?? 0))pt / 中央値 \(Markdown.number(margins.sorted()[margins.count / 2]))pt"
            + "（しきい値は \(Markdown.number(1.0, digits: 1))pt）\n"
    }

    private func analyze(_ strip: Bitmap, _ fixture: Fixture, timeText: String?) -> StatusBarAnalysis {
        StatusBarAnalyzer.analyze(strip: strip, pixelHeight: fixture.height, timeText: timeText, catalog: catalog)
    }

    // MARK: - 文字認識

    func recognition() async throws -> String {
        let analyzer = StatusBarAnalyzer(catalog: catalog)
        var rows: [[String]] = []
        let start = Date()
        for (variant, label) in Self.variantLabels {
            let targets = fixtures.filter { $0.variant == variant }
            var correct = 0
            for fixture in targets {
                let analysis = await analyzer.analyze(strip: try fixture.loadStrip(), pixelHeight: fixture.height)
                if analysis.timeText == fixture.time { correct += 1 }
            }
            rows.append([label, "\(targets.count)", "\(correct)"])
        }
        let seconds = Date().timeIntervalSince(start) / Double(max(1, fixtures.count))
        return Markdown.table(["画像", "枚数", "時刻を正しく読めた"], rows)
            + "\n1 枚あたり約 \(Markdown.number(seconds))秒（文字認識 + 判定。このテストを流した環境での値）\n"
    }

    // MARK: - 時刻の組み方

    func typography() -> String {
        let rows = catalog.layouts.map { layout -> [String] in
            let typography = TimeTypography(layout: layout)
            let errors = layout.timeSamples.map { typography.inkRect(for: $0.text).maxEdgeDistance(to: $0.ink) }
            return [
                "`\(layout.id)`", layout.models.joined(separator: "、"), Markdown.number(Double(typography.fontSize)),
                layout.timeSamples.map(\.text).joined(separator: " / "), errors.map { "\($0)" }.joined(separator: " / ")
            ]
        }
        return Markdown.table(["配置", "実測した機種", "フォントの大きさ (pt)", "実測の文字列", "見込みと実測の 4 辺の差の最大 (px)"], rows)
    }
}
