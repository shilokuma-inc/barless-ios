import PhotosUI
import SwiftUI

/// ホーム。スクリーンショットを選ぶ入口。
///
/// 写真の選択は `PhotosPicker` を使うので、写真を読む権限は求めない（選んだ 1 枚だけがアプリに渡る）
struct HomeView: View {
    /// 開いている編集。`nil` ならホームだけを表示している
    @State private var session: EditSession?
    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?

    /// - Parameter initialSession: 最初から開いておく編集（撮影モード用）
    init(initialSession: EditSession? = nil) {
        _session = State(initialValue: initialSession)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Barless")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.margin)
                .padding(.top, 28)
                .padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)
            pickButton
            Spacer(minLength: 24)
            Text("Your photos never leave this device")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        // 写真の種類は絞らない。ほかの端末から受け取ったスクリーンショットは、写真アプリで「スクリーンショット」に分類されないことがある。
        // 形式を変換させない（`.current`）のは、大きさと画素がそのままでないと機種を判定できないため
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickedItem) { _, item in
            open(item)
            // 選択を外しておく（戻ってきたときに、同じ写真をもう一度選べるように）
            pickedItem = nil
        }
        .fullScreenCover(item: $session) { session in
            EditFlowView(session: session)
        }
        .preferredColorScheme(.light)
    }

    private var pickButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 22) {
                Text("Choose a screenshot")
                    .font(.title2.bold())
                HStack(alignment: .center) {
                    Text("Hide or tidy the time, battery and signal")
                        .font(.subheadline)
                        .opacity(0.65)
                    Spacer(minLength: 12)
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, Theme.margin)
        .accessibilityIdentifier("home.pick")
    }

    private func open(_ item: PhotosPickerItem?) {
        guard let item else { return }
        session = EditSession(source: { try await item.loadTransferable(type: Data.self) })
    }
}

#Preview {
    HomeView()
}
