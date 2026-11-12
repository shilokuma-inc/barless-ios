import SwiftUI

/// 選んだ 1 枚の、編集から書き出しまで。ホームの上に全画面で出す
struct EditFlowView: View {
    let session: EditSession
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting: Bool

    init(session: EditSession) {
        self.session = session
        _isExporting = State(initialValue: session.startsInExport)
    }

    var body: some View {
        ZStack {
            Theme.darkSurface.ignoresSafeArea()
            content
        }
        .task {
            await session.start()
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .loading:
            EditPlaceholderView(onClose: close) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.darkInk)
                Text("Analyzing…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.darkInkSecondary)
            }
        case .failed:
            EditPlaceholderView(onClose: close) {
                NoticeView(title: "Couldn't open this image", detail: "Try choosing it again.")
                    .accessibilityIdentifier("edit.loadFailed")
            }
        case let .ready(screenshot):
            if isExporting, screenshot.hidden != nil {
                ExportView(image: screenshot.after, onBack: { isExporting = false }, onDone: close)
            } else {
                EditorView(screenshot: screenshot, onClose: close, onSave: { isExporting = true })
            }
        }
    }

    /// 編集をやめてホームへ戻る
    private func close() {
        dismiss()
    }
}

/// 画像がまだ無いとき（読み込みの途中・読み込めなかったとき）の画面。閉じるボタンと、中央に出す中身
private struct EditPlaceholderView<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            EditTopBar(leading: .close(onClose))
            Spacer()
            VStack(spacing: 14) {
                content
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}
