import CoreGraphics
import SwiftUI

/// エディタのモード
enum EditMode: String, CaseIterable, Sendable {
    /// ステータスバーを背景になじませて消す
    case hide
    /// 消したうえで、定番の表示（9:41・電波 4 本・Wi-Fi 最大・電池満タン）に描き直す
    case tidy
    /// 消したうえで、好きな値に描き直す
    case play

    var title: LocalizedStringKey {
        switch self {
        case .hide: "Hide"
        case .tidy: "Tidy"
        case .play: "Play"
        }
    }
}

extension EditedScreenshot {
    /// そのモードで表示・書き出しする画像。
    /// 「遊ぶ」は、値を変えた画像を `PlayModel` が持つ。ここで返すのは、値を変える前の画像（「整える」と同じ）
    func image(for mode: EditMode) -> CGImage {
        switch mode {
        case .hide: after
        case .tidy, .play: tidied ?? after
        }
    }
}
