import SwiftUI

/// 選んだ 1 枚の、編集から書き出しまで。ホームの上に全画面で出す
struct EditFlowView: View {
    let session: EditSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode: EditMode
    @State private var isComparing: Bool
    @State private var isExporting: Bool
    @State private var isAdjusting = false
    /// 手動調整の状態。調整し直すときに前の調整が残るように、編集を閉じるまで持ち続ける
    @State private var manualModel: ManualAdjustModel?

    init(session: EditSession) {
        self.session = session
        _mode = State(initialValue: session.opening.mode)
        _isComparing = State(initialValue: session.opening.isComparing)
        _isExporting = State(initialValue: session.opening.isExporting)
    }

    var body: some View {
        ZStack {
            Theme.darkSurface.ignoresSafeArea()
            content
        }
        .task {
            await session.start()
            if session.opening.isAdjusting, case let .ready(screenshot) = session.phase {
                openManualAdjust(for: screenshot)
            }
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
            if isAdjusting, let manualModel {
                ManualAdjustView(model: manualModel, onCancel: { isAdjusting = false }, onContinue: { result in
                    session.apply(result)
                    isAdjusting = false
                })
            } else if isExporting, screenshot.hasResult {
                // 選んでいるモードの画像を書き出す
                ExportView(image: exportImage(of: screenshot), onBack: { isExporting = false }, onDone: close)
            } else {
                EditorView(
                    screenshot: screenshot,
                    mode: $mode,
                    isComparing: $isComparing,
                    play: session.play,
                    onClose: close,
                    onSave: startExport,
                    onAdjust: { openManualAdjust(for: screenshot) }
                )
            }
        }
    }

    /// 書き出しの画面へ進む。「遊ぶ」で値を変えた直後でも、その値で描き終えた画像を書き出す
    private func startExport() {
        Task {
            await session.play?.waitForRender()
            isExporting = true
        }
    }

    /// 書き出す画像。「遊ぶ」では、値を変えた画像
    private func exportImage(of screenshot: EditedScreenshot) -> CGImage {
        if mode == .play, let play = session.play { return play.image }
        return screenshot.image(for: mode)
    }

    /// 手動調整の画面を開く。扱えない画像（元のデータを持っていない）では何もしない
    private func openManualAdjust(for screenshot: EditedScreenshot) {
        guard let source = screenshot.manualSource else { return }
        if manualModel == nil {
            manualModel = ManualAdjustModel(source: source, outcome: screenshot.outcome)
        }
        isAdjusting = true
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
