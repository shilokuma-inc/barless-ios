import SwiftUI

/// いくつかの選択肢から 1 つを選ぶ、横に並んだ切り替え
struct SegmentPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: Text
        let identifier: String

        init(value: Value, title: LocalizedStringKey, identifier: String) {
            self.value = value
            self.label = Text(title)
            self.identifier = identifier
        }

        /// 数字や時刻のように、どの言語でも同じ文字を出す選択肢
        init(value: Value, verbatim: String, identifier: String) {
            self.value = value
            self.label = Text(verbatim: verbatim)
            self.identifier = identifier
        }
    }

    let options: [Option]
    @Binding var selection: Value
    /// 幅いっぱいに等分するか。しないときは、文字の幅に合わせて詰める
    var fillsWidth = true
    /// 切り替えの地の色
    var track = Theme.darkSurfaceSecondary
    /// 選択肢を押したとき（選んでいるものを、もう一度押したときも）に呼ぶ
    var onTap: ((Value) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                    onTap?(option.value)
                } label: {
                    option.label
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

/// 項目の名前と、その右に置く操作（スライダー・切り替え）の 1 行。
/// 文字を大きくしていて横に入りきらないときは、操作を項目の名前の下に置く
struct OptionRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let label = Text(title)
            .font(.body)
            .foregroundStyle(Theme.darkInk)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                label
                content
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 52)
    }
}

/// 行と行のあいだの細い線
struct OptionSeparator: View {
    var body: some View {
        Theme.darkLine.frame(height: 1)
    }
}
