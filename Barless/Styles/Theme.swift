import SwiftUI

/// 画面の色。白・黒・グレーと、緑 1 色だけを使う。
///
/// ホームは明るく、編集と書き出しは黒にする（写真が正しい色で見えるように）。端末のダークモードには合わせない
enum Theme {
    // 明るい画面
    static let ink = Color(hex: 0x111112)
    static let inkSecondary = Color(hex: 0x5C5C60)
    static let surface = Color.white

    // 暗い画面
    static let darkSurface = Color(hex: 0x0E0E0F)
    static let darkSurfaceSecondary = Color(hex: 0x1B1B1D)
    static let darkSurfaceTertiary = Color(hex: 0x29292C)
    static let darkLine = Color(hex: 0x303033)
    static let darkInk = Color(hex: 0xF5F5F6)
    static let darkInkSecondary = Color(hex: 0xA3A3A8)

    /// 電池の「満タン」の緑。選択中の印と、ステータスバーの印だけに使う
    static let accent = Color(hex: 0x22C36B)
    /// 注意（跡が残るかもしれない など）
    static let warning = Color(hex: 0xFF9F0A)

    /// ボタンの角の丸み
    static let buttonRadius: CGFloat = 14
    /// 画面の左右の余白
    static let margin: CGFloat = 20
}

extension Color {
    /// `0xRRGGBB` の値から作る（sRGB）
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
