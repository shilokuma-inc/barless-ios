import DeviceCatalog
import StatusBarEditor
import SwiftUI

/// 「隠す」「整える」の結果を見る画面。自動で消せなかった画像では、その理由と、手動調整への入口を出す
struct EditorView: View {
    let screenshot: EditedScreenshot
    @Binding var mode: EditMode
    /// 比較（つまみを動かして、元の画像と見比べる）を出しているか
    @Binding var isComparing: Bool
    /// 「遊ぶ」の状態。自動で消せた画像のときだけある
    let play: PlayModel?
    let onClose: () -> Void
    let onSave: () -> Void
    /// 手動調整の画面を開く
    let onAdjust: () -> Void
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
                if screenshot.hasResult {
                    TopBarPillButton(title: "Save", action: onSave)
                        .accessibilityIdentifier("editor.save")
                }
            }
            // 「遊ぶ」の行が長くなっても、画像にはこの高さを残す
            canvas
                .frame(minHeight: 160)
                .padding(.top, 4)
                .padding(.bottom, 12)
            if let hidden = screenshot.hidden {
                HStack(spacing: 8) {
                    EditModePicker(selection: $mode)
                    CompareToggle(isOn: $isComparing)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 12)
                if mode == .play, let play {
                    PlayPanel(model: play)
                        .layoutPriority(1)
                        .padding(.bottom, 8)
                }
                HiddenSummaryView(hidden: hidden, mode: mode, isComparing: isComparing)
            } else if let manual = screenshot.manual {
                // 手動調整の結果。配置が分からないので「整える」は無い
                HStack(spacing: 8) {
                    AdjustAgainButton(action: onAdjust)
                    CompareToggle(isOn: $isComparing)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 12)
                ManualSummaryView(manual: manual, isComparing: isComparing)
            } else if case let .notHidden(failure) = screenshot.outcome {
                NotHiddenView(
                    failure: failure, onAdjust: screenshot.manualSource == nil ? nil : onAdjust, onChooseAnother: onClose
                )
            }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let bandHeight = screenshot.bandHeight {
            ScreenshotCanvas(
                image: isShowingOriginal ? screenshot.before : resultImage,
                bandHeight: bandHeight,
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

    /// 選んでいるモードの結果の画像。「遊ぶ」では、値を変えた画像
    private var resultImage: CGImage {
        if mode == .play, let play { return play.image }
        return screenshot.image(for: mode)
    }

    private var canvasLabel: Text {
        if isComparing { return Text("Comparison with the original") }
        if isShowingOriginal { return Text("Original screenshot") }
        guard screenshot.tidied != nil else { return Text("Screenshot with the status bar hidden") }
        switch mode {
        case .hide: return Text("Screenshot with the status bar hidden")
        case .tidy: return Text("Screenshot with a tidied status bar")
        case .play: return Text("Screenshot with a customized status bar")
        }
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
            // 「遊ぶ」では、値を変える行に場所を使うので、判定の結果と見比べ方の説明は出さない（注意だけ出す）
            if mode != .play {
                StatusRow(color: Theme.accent, text: Text("Detected as \(screenSize)-inch · \(generationName)"))
                    .accessibilityIdentifier("editor.detected")
            }
            if hidden.mayLeaveTraces {
                TracesWarningRow()
            }
            if mode != .play {
                CompareHint(isComparing: isComparing)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, mode == .play ? 8 : 20)
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

/// 手動調整の結果の、画像の下の説明
private struct ManualSummaryView: View {
    let manual: ManualEdit
    let isComparing: Bool

    var body: some View {
        VStack(spacing: 8) {
            StatusRow(color: Theme.accent, text: Text("Adjusted manually"))
                .accessibilityIdentifier("editor.manualSummary")
            if manual.mayLeaveTraces {
                TracesWarningRow()
            }
            CompareHint(isComparing: isComparing)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)
    }
}

/// 手動調整の画面へ戻るボタン。モードの切り替えと同じ高さ・同じ地の色にして、「比較」と並べる
private struct AdjustAgainButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Adjust again")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.darkInk)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Theme.darkSurfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("editor.adjustAgain")
    }
}

/// 色の点と 1 行の説明（判定の結果・注意）
private struct StatusRow: View {
    let color: Color
    let text: Text

    var body: some View {
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
}

/// 消した跡が残りうることの注意
private struct TracesWarningRow: View {
    var body: some View {
        StatusRow(color: Theme.warning, text: Text("The background is a photo or pattern, so some traces may remain"))
            .accessibilityIdentifier("editor.traces")
    }
}

/// 元の画像との見比べ方の説明
private struct CompareHint: View {
    let isComparing: Bool

    var body: some View {
        Text(isComparing ? "Drag the handle to compare with the original" : "Hold the image to see the original")
            .font(.caption)
            .foregroundStyle(Theme.darkInkSecondary)
            .opacity(0.8)
    }
}

/// 消せなかったときの、画像の下の説明
private struct NotHiddenView: View {
    let failure: HideFailure
    /// 手動調整へ進む。扱えない大きさの画像では `nil`（入口を出さない）
    let onAdjust: (() -> Void)?
    let onChooseAnother: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            notice
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("editor.notHidden")
            VStack(spacing: 10) {
                if let onAdjust {
                    Button("Adjust manually", action: onAdjust)
                        .buttonStyle(BlockButtonStyle(kind: .primary))
                        .accessibilityIdentifier("editor.adjustManually")
                }
                Button("Choose another screenshot", action: onChooseAnother)
                    .buttonStyle(BlockButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("editor.chooseAnother")
            }
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
