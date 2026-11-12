import SwiftUI

/// 押している間だけ少し薄くする（形と色はラベルの側で決める）
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// 幅いっぱいの、高さ 50pt のボタン
struct BlockButtonStyle: ButtonStyle {
    enum Kind {
        /// 白地に黒い文字（暗い画面の主ボタン）
        case primary
        /// 濃いグレー地に白い文字（暗い画面の副ボタン）
        case secondary
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(kind == .primary ? Color.black : Theme.darkInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(
                kind == .primary ? Color.white : Theme.darkSurfaceTertiary,
                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
