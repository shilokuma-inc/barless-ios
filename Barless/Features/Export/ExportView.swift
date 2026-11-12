import CoreGraphics
import ImageIOKit
import SwiftUI

/// 書き出し。写真への保存が主で、その下に共有を置く
struct ExportView: View {
    let image: CGImage
    let onBack: () -> Void
    let onDone: () -> Void
    @State private var model: ExportModel
    @Environment(\.openURL) private var openURL

    init(image: CGImage, onBack: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.image = image
        self.onBack = onBack
        self.onDone = onDone
        _model = State(initialValue: ExportModel(image: image))
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                EditTopBar(leading: .back(onBack)) {
                    if model.saveState == .saved {
                        TopBarPillButton(title: "Done", action: onDone)
                            .accessibilityIdentifier("export.done")
                    }
                }
                ScrollView {
                    VStack(spacing: 0) {
                        preview(height: min(440, proxy.size.height * 0.5))
                        actions
                        options
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: model.format) {
            await model.prepare()
        }
        .alert("Barless can't add to Photos", isPresented: isPresenting(.notAuthorized)) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow adding photos in Settings.")
        }
        .alert("Couldn't save the image", isPresented: isPresenting(.failed)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again.")
        }
    }

    private func preview(height: CGFloat) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(height: height)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .accessibilityHidden(true)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await model.save() }
            } label: {
                saveLabel
            }
            // 保存が済んだら、主ボタンの見た目をやめて「済んだ」ことだけを示す（押しても何も起きない）
            .buttonStyle(BlockButtonStyle(kind: model.saveState == .saved ? .secondary : .primary))
            .disabled(model.fileURL == nil || model.saveState == .saving)
            .allowsHitTesting(model.saveState == .idle)
            .accessibilityIdentifier("export.save")
            share
            if model.preparation == .failed {
                Text("Couldn't prepare the image for export")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("export.prepareFailed")
            }
        }
        .padding(.horizontal, Theme.margin)
    }

    @ViewBuilder private var saveLabel: some View {
        switch model.saveState {
        case .idle:
            Text("Save to Photos")
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.black)
                Text("Saving…")
            }
        case .saved:
            Label("Saved", systemImage: "checkmark")
        }
    }

    /// 共有。ファイルの用意ができるまでは、押せない同じ見た目のボタンを出す
    @ViewBuilder private var share: some View {
        let label = Label("Share", systemImage: "square.and.arrow.up")
        if let url = model.fileURL {
            ShareLink(item: url) {
                label
            }
            .buttonStyle(BlockButtonStyle(kind: .secondary))
            .accessibilityIdentifier("export.share")
        } else {
            Button {} label: {
                label
            }
            .buttonStyle(BlockButtonStyle(kind: .secondary))
            .disabled(true)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(Theme.darkLine)
            HStack {
                Text("Format")
                    .font(.callout)
                    .foregroundStyle(Theme.darkInk)
                Spacer(minLength: 12)
                FormatPicker(selection: $model.format)
                    // 保存の途中で形式を変えると、どちらの形式を保存したのか分からなくなる
                    .disabled(model.saveState == .saving)
            }
            .frame(minHeight: 50)
            Divider()
                .overlay(Theme.darkLine)
            Text("Location and capture date are not included")
                .font(.footnote)
                .foregroundStyle(Theme.darkInkSecondary)
                .padding(.top, 12)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    /// `problem` がその値のときだけ `true` になる（お知らせを閉じたら `nil` に戻す）
    private func isPresenting(_ problem: ExportModel.SaveProblem) -> Binding<Bool> {
        Binding(
            get: { model.problem == problem },
            set: { isPresented in
                if !isPresented, model.problem == problem { model.problem = nil }
            }
        )
    }
}

/// 形式（PNG / HEIC）の切り替え
private struct FormatPicker: View {
    @Binding var selection: ImageFileFormat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ImageFileFormat.allCases, id: \.self) { format in
                let isSelected = format == selection
                Button {
                    selection = format
                } label: {
                    Text(verbatim: format.rawValue.uppercased())
                        .font(.footnote.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Theme.darkInkSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? Theme.darkSurfaceTertiary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("export.format.\(format.rawValue)")
            }
        }
        .padding(2)
        .background(Theme.darkSurfaceSecondary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
