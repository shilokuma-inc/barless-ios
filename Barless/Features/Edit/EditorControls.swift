import SwiftUI

/// いくつかの選択肢から 1 つを選ぶ、横に並んだ切り替え
struct SegmentPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: LocalizedStringKey
        let identifier: String
    }

    let options: [Option]
    @Binding var selection: Value
    /// 幅いっぱいに等分するか。しないときは、文字の幅に合わせて詰める
    var fillsWidth = true
    /// 切り替えの地の色
    var track = Theme.darkSurfaceSecondary

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Theme.darkInkSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, fillsWidth ? 0 : 12)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Theme.darkSurfaceTertiary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(option.identifier)
            }
        }
        .padding(2)
        .background(track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// モード（隠す / 整える）の切り替え
struct EditModePicker: View {
    @Binding var selection: EditMode

    var body: some View {
        SegmentPicker(
            options: EditMode.allCases.map { .init(value: $0, title: $0.title, identifier: "editor.mode.\($0.rawValue)") },
            selection: $selection
        )
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
