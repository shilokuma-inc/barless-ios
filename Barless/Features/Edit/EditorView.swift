import DeviceCatalog
import StatusBarEditor
import SwiftUI

/// 「隠す」「整える」の結果を見る画面
struct EditorView: View {
    let screenshot: EditedScreenshot
    @Binding var mode: EditMode
    /// 比較（つまみを動かして、元の画像と見比べる）を出しているか
    @Binding var isComparing: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    /// 画像を押している間だけ `true`。指を離したときも、ジェスチャーが取り消されたとき（着信・通知など）も `false` に戻る
    @GestureState private var isPressing = false
    /// 読み上げの操作で、元の画像に切り替えているか（押し続ける操作の代わり）
    @State private var isOriginalPinned = false
    /// 比較の境の位置（0〜1。左が元の画像）
    @State private var comparePosition: CGFloat = 0.5

    /// 元の画像を出しているか（比較のときは、つまみで見比べるので使わない）
    private var isShowingOriginal: Bool {
        !isComparing && (isPressing || isOriginalPinned)
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
                HStack(spacing: 8) {
                    EditModePicker(selection: $mode)
                    CompareToggle(isOn: $isComparing)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 12)
                HiddenSummaryView(hidden: hidden, mode: mode, isComparing: isComparing)
            } else if case let .notHidden(failure) = screenshot.outcome {
                NotHiddenView(failure: failure, onChooseAnother: onClose)
            }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let hidden = screenshot.hidden {
            ScreenshotCanvas(
                image: isShowingOriginal ? screenshot.before : screenshot.image(for: mode),
                bandHeight: hidden.bandHeight,
                tag: isShowingOriginal ? "BEFORE" : nil,
                comparison: isComparing ? .init(before: screenshot.before, position: $comparePosition) : nil
            )
            .contentShape(Rectangle())
            // 押している間だけ元の画像を出す。長押しのジェスチャーは成立した時点で「押している」が切れるので、移動 0 のドラッグで代える
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true },
                isEnabled: !isComparing
            )
            .accessibilityElement()
            .accessibilityLabel(canvasLabel)
            .accessibilityAddTraits(.isImage)
            .modifier(CanvasAccessibility(isComparing: isComparing, position: $comparePosition, isOriginalPinned: $isOriginalPinned))
            .accessibilityIdentifier("editor.canvas")
        } else {
            ScreenshotCanvas(image: screenshot.after)
                .accessibilityHidden(true)
        }
    }

    private var canvasLabel: Text {
        if isComparing { return Text("Comparison with the original") }
        if isShowingOriginal { return Text("Original screenshot") }
        return mode == .tidy ? Text("Screenshot with a tidied status bar") : Text("Screenshot with the status bar hidden")
    }
}

/// 画像の読み上げ用の操作。比較のときは境を左右に動かし、それ以外は元の画像との切り替え
private struct CanvasAccessibility: ViewModifier {
    let isComparing: Bool
    @Binding var position: CGFloat
    @Binding var isOriginalPinned: Bool

    func body(content: Content) -> some View {
        if isComparing {
            content
                .accessibilityValue(Text("\(Int((position * 100).rounded()))%"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: position = min(1, position + 0.1)
                    case .decrement: position = max(0, position - 0.1)
                    @unknown default: break
                    }
                }
        } else {
            content
                .accessibilityAction(named: isOriginalPinned ? Text("Show the result") : Text("Show the original")) {
                    isOriginalPinned.toggle()
                }
        }
    }
}

/// 消せたときの、画像の下の説明
private struct HiddenSummaryView: View {
    let hidden: HiddenStatusBar
    let mode: EditMode
    let isComparing: Bool

    var body: some View {
        VStack(spacing: 8) {
            if mode == .tidy {
                // 「整える」で描き直す中身
                Text("9:41 · 4 bars · Full Wi-Fi · Battery 100%")
                    .font(.caption)
                    .foregroundStyle(Theme.darkInkSecondary)
                    .accessibilityIdentifier("editor.tidySummary")
            }
            statusRow(color: Theme.accent, text: Text("Detected as \(screenSize)-inch · \(generationName)"))
                .accessibilityIdentifier("editor.detected")
            if hidden.mayLeaveTraces {
                statusRow(color: Theme.warning, text: Text("The background is a photo or pattern, so some traces may remain"))
                    .accessibilityIdentifier("editor.traces")
            }
            Text(isComparing ? "Drag the handle to compare with the original" : "Hold the image to see the original")
                .font(.caption)
                .foregroundStyle(Theme.darkInkSecondary)
                .opacity(0.8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.margin)
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

    /// 画面の大きさ（「6.3」）。機種名は出さない。同じ大きさの画面を持つ機種がいくつもあり、
    /// カタログの機種名（実測した機種）を出すと、別の機種で撮った人には誤った判定に見えるため
    private var screenSize: String {
        hidden.layout.screenInches.formatted(.number.precision(.fractionLength(1)))
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
