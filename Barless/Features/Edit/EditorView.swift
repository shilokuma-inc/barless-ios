import DeviceCatalog
import StatusBarEditor
import SwiftUI

/// 「隠す」の結果を見る画面
struct EditorView: View {
    let screenshot: EditedScreenshot
    let onClose: () -> Void
    let onSave: () -> Void
    /// 画像を押している間だけ `true`。指を離したときも、ジェスチャーが取り消されたとき（着信・通知など）も `false` に戻る
    @GestureState private var isPressing = false
    /// 読み上げの操作で、元の画像に切り替えているか（押し続ける操作の代わり）
    @State private var isOriginalPinned = false

    /// 元の画像を出しているか
    private var isShowingOriginal: Bool {
        isPressing || isOriginalPinned
    }

    var body: some View {
        VStack(spacing: 0) {
            EditTopBar(leading: .close(onClose)) {
                if screenshot.hidden != nil {
                    TopBarPillButton(title: "Save", action: onSave)
                        .accessibilityIdentifier("editor.save")
                }
            }
            canvas
                .padding(.top, 4)
                .padding(.bottom, 12)
            if let hidden = screenshot.hidden {
                HiddenSummaryView(hidden: hidden)
            } else if case let .notHidden(failure) = screenshot.outcome {
                NotHiddenView(failure: failure, onChooseAnother: onClose)
            }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let hidden = screenshot.hidden {
            ScreenshotCanvas(
                image: isShowingOriginal ? screenshot.before : screenshot.after,
                bandHeight: hidden.bandHeight,
                tag: isShowingOriginal ? "Original" : nil
            )
            .contentShape(Rectangle())
            // 押している間だけ元の画像を出す。長押しのジェスチャーは成立した時点で「押している」が切れるので、移動 0 のドラッグで代える
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
            )
            .accessibilityElement()
            .accessibilityLabel(isShowingOriginal ? Text("Original screenshot") : Text("Screenshot with the status bar hidden"))
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: isShowingOriginal ? Text("Show the result") : Text("Show the original")) {
                isOriginalPinned.toggle()
            }
            .accessibilityIdentifier("editor.canvas")
        } else {
            ScreenshotCanvas(image: screenshot.after)
                .accessibilityHidden(true)
        }
    }
}

/// 消せたときの、画像の下の説明
private struct HiddenSummaryView: View {
    let hidden: HiddenStatusBar

    var body: some View {
        VStack(spacing: 8) {
            statusRow(color: Theme.accent, text: Text("Detected as \(modelName) size · \(generationName)"))
                .accessibilityIdentifier("editor.detected")
            if hidden.mayLeaveTraces {
                statusRow(color: Theme.warning, text: Text("The background is a photo or pattern, so some traces may remain"))
                    .accessibilityIdentifier("editor.traces")
            }
            Text("Hold the image to see the original")
                .font(.caption)
                .foregroundStyle(Theme.darkInkSecondary)
                .opacity(0.8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private func statusRow(color: Color, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                .accessibilityHidden(true)
            text
                .font(.caption)
                .foregroundStyle(Theme.darkInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 実測した機種の名前。同じ大きさの画面を持つ機種はほかにもあるので、「〜相当」として出す
    private var modelName: String {
        hidden.layout.models.first ?? "iPhone"
    }

    private var generationName: String {
        switch hidden.layout.generation {
        case .iOS18to26: String(localized: "iOS 18–26")
        case .iOS27: "iOS 27"
        }
    }
}

/// 消せなかったときの、画像の下の説明
private struct NotHiddenView: View {
    let failure: HideFailure
    let onChooseAnother: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            notice
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("editor.notHidden")
            Button("Choose another screenshot", action: onChooseAnother)
                .buttonStyle(BlockButtonStyle(kind: .secondary))
                .accessibilityIdentifier("editor.chooseAnother")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private var notice: NoticeView {
        switch failure {
        case .unknownSize:
            NoticeView(
                title: "Couldn't tell where the status bar is",
                detail: "Choose an iPhone screenshot that hasn't been cropped or resized."
            )
        case .unsupportedScreen:
            NoticeView(title: "Screenshots from this iPhone aren't supported yet")
        case .undetermined:
            NoticeView(
                title: "Couldn't find the status bar",
                detail: "Choose an iPhone screenshot that shows the time, signal and battery at the top."
            )
        }
    }
}
