import CoreGraphics
import ImageIOKit
import Observation
import StatusBarEditor

/// 手動調整の画面の状態。帯の高さ・文字の色・背景を変えるたびに、途中の結果を作り直す
@MainActor
@Observable
final class ManualAdjustModel {
    enum Phase {
        /// 元の大きさの画像を読み込んでいる
        case loading
        case ready(ManualCanvas)
        case failed
    }

    /// 背景の埋め方の選択肢（画面の切り替えの 3 つ）
    enum BackgroundMode: String, CaseIterable, Sendable {
        case automatic
        /// 画像から拾った 1 色で塗る
        case pickColor
        case blur
    }

    private(set) var phase: Phase = .loading
    private(set) var bandHeight = 0
    private(set) var textColor = ManualAdjustment.TextColor.automatic
    private(set) var backgroundMode = BackgroundMode.automatic
    /// 「色を拾う」で塗る色。拾う前は、帯のすぐ下の中央の色
    private(set) var pickedColor: RGB?
    /// いまの調整を当てた、途中の結果。まだ無いときは `nil`
    private(set) var preview: ManualPreview?
    /// 「この設定で続ける」の処理の途中か
    private(set) var isFinishing = false

    private let source: ManualSource
    private let outcome: HideOutcome
    private let processor = ManualProcessor()
    private var hasStarted = false
    /// 「この設定で続ける」を数える番号。処理を待っている間に取り消されたら、番号が進んでいるので、結果を捨てる
    private var finishGeneration = 0
    /// まだ途中の結果を作っていない、いちばん新しい調整
    private var pendingAdjustment: ManualAdjustment?
    /// 途中の結果を作っている処理。作り終えると `nil` に戻る
    private var renderTask: Task<Void, Never>?

    /// - Parameter outcome: 自動の判定の結果（消せなかった理由）。調整の結果に引き継ぐ
    init(source: ManualSource, outcome: HideOutcome) {
        self.source = source
        self.outcome = outcome
    }

    /// いまの調整
    var adjustment: ManualAdjustment {
        let background: ManualAdjustment.Background = switch backgroundMode {
        case .automatic: .automatic
        case .pickColor: .color(pickedColor ?? .white)
        case .blur: .blur
        }
        return ManualAdjustment(bandHeight: bandHeight, textColor: textColor, background: background)
    }

    /// 読み込む。2 回目以降の呼び出しでは何もしない（調整し直すときに、前の調整を残すため）
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let canvas = try await processor.load(source)
            bandHeight = canvas.editor.suggestedBandHeight
            phase = .ready(canvas)
            render()
        } catch {
            phase = .failed
        }
    }

    // 調整は、「この設定で続ける」の処理の途中では変えない（書き出す結果と、画面に残る調整がずれないように）

    func setBandHeight(_ height: Int) {
        guard !isFinishing, case let .ready(canvas) = phase else { return }
        let clamped = canvas.editor.clamped(height)
        guard clamped != bandHeight else { return }
        bandHeight = clamped
        render()
    }

    func setTextColor(_ color: ManualAdjustment.TextColor) {
        guard !isFinishing, color != textColor else { return }
        textColor = color
        render()
    }

    func setBackgroundMode(_ mode: BackgroundMode) {
        guard !isFinishing, mode != backgroundMode, case let .ready(canvas) = phase else { return }
        backgroundMode = mode
        if mode == .pickColor, pickedColor == nil {
            // 最初は、帯のすぐ下の色にしておく（ステータスバーの下に続く背景の色であることが多い）
            pickedColor = processor.color(in: canvas, x: canvas.original.width / 2, y: bandHeight)
        }
        render()
    }

    /// 画像のその位置（px）の色を拾う。「色を拾う」を選んでいるときだけ働く
    func pickColor(x: Int, y: Int) {
        guard !isFinishing, backgroundMode == .pickColor, case let .ready(canvas) = phase,
              let color = processor.color(in: canvas, x: x, y: y), color != pickedColor else { return }
        pickedColor = color
        render()
    }

    /// 画像の全体に、いまの調整を当てた結果。作れなければ `nil` を返し、「開けませんでした」の表示に切り替える。
    /// 待っている間に `cancelFinish()` で取り消されたときも `nil`（結果は使わない）
    func finish() async -> EditedScreenshot? {
        guard case let .ready(canvas) = phase, !isFinishing else { return nil }
        isFinishing = true
        defer { isFinishing = false }
        finishGeneration += 1
        let generation = finishGeneration
        do {
            let result = try await processor.apply(adjustment, to: canvas, source: source, outcome: outcome)
            return generation == finishGeneration ? result : nil
        } catch {
            phase = .failed
            return nil
        }
    }

    /// 「この設定で続ける」の処理の途中で、調整の画面から戻るとき。処理が終わっても、その結果は使わない
    func cancelFinish() {
        finishGeneration += 1
    }

    /// 途中の結果が、いまの調整に追いつくまで待つ（テスト用）
    func waitForPreview() async {
        await renderTask?.value
    }

    /// 途中の結果を作り直す。作っている間に調整が変わったら、いちばん新しいものだけを続けて作る
    private func render() {
        guard case let .ready(canvas) = phase else { return }
        pendingAdjustment = adjustment
        guard renderTask == nil else { return }
        renderTask = Task {
            while let next = pendingAdjustment {
                pendingAdjustment = nil
                if let result = try? await processor.preview(next, on: canvas) {
                    preview = result
                }
            }
            renderTask = nil
        }
    }
}
