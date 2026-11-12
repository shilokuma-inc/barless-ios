import ImageIOKit
import StatusBarEditor
import SwiftUI

/// 手動調整の画面。機種を判定できなかった画像で、ステータスバーの帯の高さを自分で合わせる。
///
/// 画像には、いまの調整を当てた結果をその場で出す。緑の線を下げていき、ステータスバーが消えたところで止めればよい
struct ManualAdjustView: View {
    let model: ManualAdjustModel
    /// 調整をやめて、前の画面へ戻る
    let onCancel: () -> Void
    /// 「この設定で続ける」。画像の全体に調整を当てた結果を渡す
    let onContinue: (EditedScreenshot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditTopBar(leading: .back {
                // 「続ける」の処理の途中で戻ったら、その結果は当てない
                model.cancelFinish()
                onCancel()
            })
            switch model.phase {
            case .loading:
                placeholder {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.darkInk)
                }
            case .failed:
                placeholder {
                    NoticeView(title: "Couldn't open this image", detail: "Try choosing it again.")
                }
            case let .ready(canvas):
                // 文字を大きくしていて調整の中身が長くなっても、画像にはこの高さを残す（中身のほうをスクロールさせる）
                ManualCanvasView(model: model, canvas: canvas)
                    .frame(minHeight: 160)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                ManualPanel(model: model, canvas: canvas, onContinue: onContinue)
                    .layoutPriority(1)
            }
        }
        .task {
            await model.start()
        }
    }

    private func placeholder(@ViewBuilder content: () -> some View) -> some View {
        VStack {
            Spacer()
            content()
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

/// 画像と、帯の下端を示す緑の線
private struct ManualCanvasView: View {
    let model: ManualAdjustModel
    let canvas: ManualCanvas
    /// つまみを動かし始めたときの、帯の高さ（px）。動かしている間だけ値が入る。
    /// 指を離したときも、ジェスチャーが取り消されたとき（着信・通知など）も `nil` に戻る
    @GestureState private var heightAtDragStart: Int?

    /// 画像の左右に空けておく幅。線（画像の 14pt 外側まで）と、その右端のつまみが画面の端にかからないようにする
    private static let sideInset: CGFloat = 28
    private static let lineOverhang: CGFloat = 14
    private static let knobSize: CGFloat = 26
    /// つまみの、指で押せる範囲
    private static let knobHitSize: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let image = canvas.original
            let size = image.fittedSize(in: proxy.size, sideInset: Self.sideInset)
            let pixelsPerPoint = CGFloat(image.height) / size.height
            let lineY = CGFloat(model.bandHeight) / pixelsPerPoint
            picture(size: size, lineY: lineY)
                .contentShape(Rectangle())
                // 「色を拾う」のとき、画像をなぞったところの色を拾う
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.pickColor(
                                x: Int(value.location.x * pixelsPerPoint), y: Int(value.location.y * pixelsPerPoint)
                            )
                        },
                    isEnabled: model.backgroundMode == .pickColor
                )
                .overlay(alignment: .topLeading) {
                    line(width: size.width, pixelsPerPoint: pixelsPerPoint)
                        .offset(x: -Self.lineOverhang, y: lineY - Self.knobHitSize / 2)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Screenshot with the status bar hidden")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("manual.canvas")
    }

    /// 元の画像の上端に、いまの調整を当てた結果を重ねる。重ねるのは線の上（帯の中）だけ
    private func picture(size: CGSize, lineY: CGFloat) -> some View {
        Image(decorative: canvas.original, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                if let preview = model.preview {
                    let stripHeight = size.height * CGFloat(preview.strip.height) / CGFloat(max(1, canvas.original.height))
                    Image(decorative: preview.strip, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: stripHeight)
                        .mask(alignment: .top) {
                            Rectangle()
                                .frame(height: min(lineY, stripHeight))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 緑の線と、右端のつまみ。つまみを上下に動かすと、帯の高さが変わる
    private func line(width: CGFloat, pixelsPerPoint: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Theme.accent
                .frame(height: 2)
                .padding(.trailing, Self.knobHitSize / 2)
            Image(systemName: "arrow.up.and.down")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.black)
                .frame(width: Self.knobSize, height: Self.knobSize)
                .background(Theme.accent, in: Circle())
                .frame(width: Self.knobHitSize, height: Self.knobHitSize)
                .contentShape(Rectangle())
                // 線は指と一緒に動くので、動かない画面の座標で移動量を読む
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .updating($heightAtDragStart) { _, start, _ in
                            start = start ?? model.bandHeight
                        }
                        .onChanged { value in
                            // 動かし始めの 1 回目は、まだ値が入っていないので、いまの高さを使う（移動量は 0）
                            let start = heightAtDragStart ?? model.bandHeight
                            model.setBandHeight(start + Int((value.translation.height * pixelsPerPoint).rounded()))
                        }
                )
        }
        // つまみの中心を、線の右端（画像の 14pt 外側）に合わせる
        .frame(width: width + 2 * Self.lineOverhang + Self.knobHitSize / 2, height: Self.knobHitSize)
        .accessibilityHidden(true)
    }
}

/// 画像の下の、調整の中身
private struct ManualPanel: View {
    let model: ManualAdjustModel
    let canvas: ManualCanvas
    let onContinue: (EditedScreenshot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 入りきらないときは、調整の中身だけをスクロールさせる。「続ける」は、いつも見えるところに置く
            ViewThatFits(in: .vertical) {
                options
                ScrollView {
                    options
                }
            }
            Button("Continue with these settings") {
                Task {
                    if let result = await model.finish() { onContinue(result) }
                }
            }
            .buttonStyle(BlockButtonStyle(kind: .primary))
            .disabled(model.isFinishing)
            .accessibilityIdentifier("manual.continue")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(Theme.darkSurfaceSecondary)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 説明と、高さ・文字の色・背景の行
    private var options: some View {
        VStack(spacing: 0) {
            message
                .padding(.bottom, 12)
            OptionSeparator()
            OptionRow("Height") {
                heightSlider
            }
            OptionSeparator()
            OptionRow("Text color") {
                SegmentPicker(
                    options: [
                        .init(value: .automatic, title: "Auto", identifier: "manual.textColor.automatic"),
                        .init(value: .white, title: "White", identifier: "manual.textColor.white"),
                        .init(value: .black, title: "Black", identifier: "manual.textColor.black")
                    ],
                    selection: Binding(get: { model.textColor }, set: { model.setTextColor($0) }),
                    fillsWidth: false,
                    track: Theme.darkSurface
                )
            }
            // 文字の色は、文字とアイコンを拾って消すとき（背景が「自動」）だけ使う
            .disabled(model.backgroundMode != .automatic)
            .opacity(model.backgroundMode == .automatic ? 1 : 0.4)
            OptionSeparator()
            OptionRow("Background") {
                SegmentPicker(
                    options: [
                        .init(value: .automatic, title: "Auto", identifier: "manual.background.automatic"),
                        .init(value: .pickColor, title: "Pick color", identifier: "manual.background.pickColor"),
                        .init(value: .blur, title: "Blur", identifier: "manual.background.blur")
                    ],
                    selection: Binding(get: { model.backgroundMode }, set: { model.setBackgroundMode($0) }),
                    fillsWidth: false,
                    track: Theme.darkSurface
                )
            }
            OptionSeparator()
            // 補足が出たり消えたりしても、画像の大きさが変わらないように、いつも同じ高さを取っておく
            ZStack {
                footnote
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        // 「続ける」の処理の途中は、調整を変えられない
        .disabled(model.isFinishing)
    }

    private var message: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't identify the device")
                    .font(.headline)
                    .foregroundStyle(Theme.darkInk)
                Text("Move the green line to just below the status bar.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.darkInkSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("manual.message")
    }

    private var heightSlider: some View {
        HStack(spacing: 12) {
            Slider(
                value: Binding(get: { Double(model.bandHeight) }, set: { model.setBandHeight(Int($0.rounded())) }),
                in: Double(canvas.editor.bandHeightRange.lowerBound)...Double(canvas.editor.bandHeightRange.upperBound),
                step: 1
            )
            .tint(.white)
            .accessibilityLabel("Status bar height")
            .accessibilityValue(Text(verbatim: "\(model.bandHeight) px"))
            .accessibilityIdentifier("manual.height")
            Text(verbatim: "\(model.bandHeight) px")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.darkInkSecondary)
                .frame(minWidth: 58, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// 選んでいる背景に応じた補足。拾った色か、跡が残りそうなときの注意
    @ViewBuilder private var footnote: some View {
        if model.backgroundMode == .pickColor {
            HStack(spacing: 8) {
                if let color = model.pickedColor {
                    Circle()
                        .fill(Color(color, in: canvas.strip.colorSpace))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Theme.darkLine, lineWidth: 1))
                        .accessibilityHidden(true)
                }
                Text("Tap the image to pick the fill color")
                    .font(.caption)
                    .foregroundStyle(Theme.darkInkSecondary)
            }
            .accessibilityIdentifier("manual.pickHint")
        } else if model.preview?.mayLeaveTraces == true {
            Text("Traces may remain with this background. Try Blur or Pick color.")
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("manual.traces")
        }
    }
}

extension Color {
    /// 画像の画素の色を、その画像の色空間のまま画面に出す
    init(_ color: RGB, in colorSpace: CGColorSpace) {
        let components = [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, 1]
        if let cgColor = CGColor(colorSpace: colorSpace, components: components) {
            self.init(cgColor: cgColor)
        } else {
            self.init(.sRGB, red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
        }
    }
}
