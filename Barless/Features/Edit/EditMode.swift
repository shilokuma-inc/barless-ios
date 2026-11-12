import CoreGraphics
import SwiftUI

/// エディタのモード
enum EditMode: String, CaseIterable, Sendable {
    /// ステータスバーを背景になじませて消す
    case hide
    /// 消したうえで、定番の表示（9:41・電波 4 本・Wi-Fi 最大・電池満タン）に描き直す
    case tidy

    var title: LocalizedStringKey {
        switch self {
        case .hide: "Hide"
        case .tidy: "Tidy"
        }
    }
}

extension EditedScreenshot {
    /// そのモードで表示・書き出しする画像
    func image(for mode: EditMode) -> CGImage {
        switch mode {
        case .hide: after
        case .tidy: tidied ?? after
        }
    }
}
