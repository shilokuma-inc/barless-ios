import SwiftUI

/// 編集と書き出しの画面の上端。左に「閉じる」か「戻る」、右に操作を 1 つ置く
struct EditTopBar<Trailing: View>: View {
    /// 左のボタン
    struct Leading {
        let label: LocalizedStringKey
        let identifier: String
        let action: () -> Void

        /// 編集をやめてホームへ戻る
        static func close(_ action: @escaping () -> Void) -> Leading {
            Leading(label: "Close", identifier: "edit.close", action: action)
        }

        /// 1 つ前の画面へ戻る
        static func back(_ action: @escaping () -> Void) -> Leading {
            Leading(label: "Back", identifier: "edit.back", action: action)
        }
    }

    let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: leading.action) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.darkInk)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(leading.label)
            .accessibilityIdentifier(leading.identifier)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
    }
}

extension EditTopBar where Trailing == EmptyView {
    init(leading: Leading) {
        self.init(leading: leading) {
            EmptyView()
        }
    }
}

/// 上端の右に置く、白い丸いボタン（「保存」「完了」）
struct TopBarPillButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.white, in: Capsule())
                // 押せないときは薄くする
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 中央に出すお知らせ（読み込めなかった・消せなかった など）
struct NoticeView: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.darkInk)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.darkInkSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
