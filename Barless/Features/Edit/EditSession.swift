import Foundation
import Observation

/// 選んだ画像 1 枚の、読み込みから結果が出るまで
@MainActor
@Observable
final class EditSession: Identifiable {
    enum Phase {
        /// 読み込みと解析の途中
        case loading
        case ready(EditedScreenshot)
        /// 画像を読み込めなかった
        case failed
    }

    /// 画像のデータを取り出す処理（写真の選択なら `PhotosPickerItem` から読む）。取り出せなければ `nil`
    typealias ImageSource = @Sendable () async throws -> Data?

    nonisolated let id = UUID()
    private(set) var phase: Phase = .loading
    /// 開いた直後に書き出しの画面を出すか（撮影モード用）
    let startsInExport: Bool

    private let source: ImageSource
    private let hider: any ScreenshotHiding
    private var hasStarted = false

    init(source: @escaping ImageSource, hider: any ScreenshotHiding = StatusBarHider(), startsInExport: Bool = false) {
        self.source = source
        self.hider = hider
        self.startsInExport = startsInExport
    }

    /// 読み込んで解析する。2 回目以降の呼び出しでは何もしない（画面が出るたびに呼ばれてもよいように）
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            guard let data = try await source() else {
                phase = .failed
                return
            }
            phase = .ready(try await hider.hide(imageData: data))
        } catch {
            phase = .failed
        }
    }
}
