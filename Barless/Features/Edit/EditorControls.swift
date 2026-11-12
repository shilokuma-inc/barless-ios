import SwiftUI

/// モード（隠す / 整える）の切り替え
struct EditModePicker: View {
    @Binding var selection: EditMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditMode.allCases, id: \.self) { mode in
                let isSelected = mode == selection
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Theme.darkInkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Theme.darkSurfaceTertiary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("editor.mode.\(mode.rawValue)")
            }
        }
        .padding(2)
        .background(Theme.darkSurfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 「比較」（元の画像と結果を、つまみを動かして見比べる）の入り切り
struct CompareToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: "square.split.2x1")
                .font(.body.weight(.medium))
                .foregroundStyle(isOn ? Color.white : Theme.darkInkSecondary)
                .frame(width: 44, height: 36)
                .background(
                    isOn ? Theme.darkSurfaceTertiary : Theme.darkSurfaceSecondary,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Compare")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("editor.compare")
    }
}
