import ImageIOKit
import InpaintEngine
import StatusBarAnalyzer

/// 手動調整の中身。機種を判定できなかった画像で、利用者が決める
public struct ManualAdjustment: Sendable, Equatable {
    /// 文字とアイコンの色
    public enum TextColor: String, Sendable, CaseIterable {
        /// 背景と違う色のものを、明るくても暗くても消す
        case automatic
        case white
        case black
    }

    /// 帯の埋め方
    public enum Background: Sendable, Equatable {
        /// 文字とアイコンだけを拾って、まわりの背景で埋める
        case automatic
        /// 帯の全体を 1 色で塗る
        case color(RGB)
        /// 帯の全体をぼかす
        case blur
    }

    /// ステータスバーの帯の高さ（px。画像の上端から）
    public var bandHeight: Int
    public var textColor: TextColor
    public var background: Background

    public init(bandHeight: Int, textColor: TextColor = .automatic, background: Background = .automatic) {
        self.bandHeight = bandHeight
        self.textColor = textColor
        self.background = background
    }
}

/// 手動調整の結果
public struct ManualEditResult: Sendable {
    /// 帯を消した画像。渡した画像と同じ大きさ
    public let bitmap: Bitmap
    /// 消した跡が残りそうか。「自動」で、背景が写真・模様のときなど。1 色で塗る・ぼかすでは `false`
    public let mayLeaveTraces: Bool
}

/// 配置（機種）が分からない画像のステータスバーを、利用者が合わせた帯の高さで隠す。
///
/// 帯の中の画素だけを読み書きするので、上端だけを切り出した画像（`stripHeight` 行以上）に当てても、
/// 画像の全体に当てても、同じ結果になる。調整の途中は切り出しに当てて、すぐに結果を見せられる
public struct ManualEditor: Sendable, Equatable {
    /// 手動調整で扱う画像の大きさ（px）。小さすぎる画像と、カメラの写真のような巨大な画像は扱わない
    static let supportedSide = 200...4096
    /// 帯の高さの上限。画像の高さに対する割合。いちばん高いステータスバー（Dynamic Island の機種）で 7% ほど
    static let maxBandFraction = 0.12

    public let pixelWidth: Int
    public let pixelHeight: Int
    /// 1pt が何 px かの見込み。短い辺が 390pt 前後とみなす
    public let scale: Int

    public init(pixelWidth: Int, pixelHeight: Int) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = max(1, min(3, Int((Double(min(pixelWidth, pixelHeight)) / 390).rounded())))
    }

    /// 手動調整で扱える大きさか
    public static func supports(pixelWidth: Int, pixelHeight: Int) -> Bool {
        supportedSide.contains(pixelWidth) && supportedSide.contains(pixelHeight)
    }

    /// 帯の高さとして選べる範囲（px）
    public var bandHeightRange: ClosedRange<Int> {
        let minimum = min(4 * scale, max(3, pixelHeight / 2))
        let maximum = max(minimum, Int(Double(pixelHeight) * Self.maxBandFraction))
        return minimum...maximum
    }

    /// 最初に出す帯の高さ（px）。画像の形から見込む。
    ///
    /// 縦に長い画像（ノッチ・Dynamic Island の機種）は、どの機種でも文字とアイコンが高さの 5.1% までに収まるので 5.6%。
    /// ホームボタンの機種は 3.0%、それより横に広い画像（iPad など）は 2.4%
    public var suggestedBandHeight: Int {
        let ratio = Double(pixelWidth) / Double(pixelHeight)
        let fraction = ratio < 0.5 ? 0.056 : (ratio < 0.65 ? 0.030 : 0.024)
        return clamped(Int((Double(pixelHeight) * fraction).rounded()))
    }

    /// 調整の途中の結果を作るのに要る、上端の切り出しの高さ（px）
    public var stripHeight: Int {
        min(pixelHeight, bandHeightRange.upperBound)
    }

    public func clamped(_ bandHeight: Int) -> Int {
        min(max(bandHeight, bandHeightRange.lowerBound), bandHeightRange.upperBound)
    }

    /// 帯を隠す。`bitmap` は、画像の全体か、上端から `stripHeight` 行以上を切り出したもの
    public func apply(_ adjustment: ManualAdjustment, to bitmap: Bitmap) -> ManualEditResult {
        let bandHeight = min(clamped(adjustment.bandHeight), bitmap.height)
        switch adjustment.background {
        case .automatic:
            return erased(bitmap, bandHeight: bandHeight, textColor: adjustment.textColor)
        case let .color(color):
            var result = bitmap
            for y in 0..<bandHeight {
                for x in 0..<bitmap.width {
                    result[x, y] = color
                }
            }
            return ManualEditResult(bitmap: result, mayLeaveTraces: false)
        case .blur:
            return ManualEditResult(bitmap: BandBlur().blur(bitmap, bandHeight: bandHeight), mayLeaveTraces: false)
        }
    }

    /// 文字とアイコンを拾って、まわりの背景で埋める。単色なら 1 色で塗り、それ以外は周りから補間する
    private func erased(_ bitmap: Bitmap, bandHeight: Int, textColor: ManualAdjustment.TextColor) -> ManualEditResult {
        let tone: InkTone = switch textColor {
        case .automatic: .any
        case .white: .light
        case .black: .dark
        }
        guard let scan = ManualBandScanner(scale: scale).scan(bitmap, bandHeight: bandHeight, tone: tone),
              !scan.eraseMask.isEmpty else {
            return ManualEditResult(bitmap: bitmap, mayLeaveTraces: false)
        }
        let filled = scan.background == .solid
            ? SolidFillInpainter().fill(bitmap, mask: scan.eraseMask)
            : GradientInpainter().fill(bitmap, mask: scan.eraseMask)
        return ManualEditResult(bitmap: filled, mayLeaveTraces: scan.mayLeaveTraces)
    }
}
