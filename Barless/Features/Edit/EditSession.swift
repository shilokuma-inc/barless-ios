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

    /// 開いた直後の画面の状態。ふだんは既定のまま（「隠す」の結果）。撮影モードで、ほかの状態から始めるのに使う
    struct Opening: Sendable {
        var mode = EditMode.hide
        /// 比較（つまみを動かして見比べる）を出しておくか
        var isComparing = false
        /// 書き出しの画面を出しておくか
        var isExporting = false
        /// 手動調整の画面を出しておくか（自動で消せなかった画像のときだけ働く）
        var isAdjusting = false
    }

    nonisolated let id = UUID()
    private(set) var phase: Phase = .loading
    let opening: Opening

    private let source: ImageSource
    private let processor: any ScreenshotProcessing
    private var hasStarted = false

    init(source: @escaping ImageSource, processor: any ScreenshotProcessing = ScreenshotProcessor(), opening: Opening = Opening()) {
        self.source = source
        self.processor = processor
        self.opening = opening
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
            phase = .ready(try await processor.process(imageData: data))
        } catch {
            phase = .failed
        }
    }

    /// 手動調整の結果に置き換える
    func apply(_ screenshot: EditedScreenshot) {
        guard case .ready = phase else { return }
        phase = .ready(screenshot)
    }
}
