import Foundation

/// 検証結果の表（Markdown）を作る
enum Markdown {
    static func table(_ header: [String], _ rows: [[String]]) -> String {
        let lines = ["| " + header.joined(separator: " | ") + " |", "|" + header.map { _ in " --- |" }.joined()]
            + rows.map { "| " + $0.joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n") + "\n"
    }

    static func number(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }
}
