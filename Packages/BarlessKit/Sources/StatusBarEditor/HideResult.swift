import CoreGraphics
import DeviceCatalog
import StatusBarAnalyzer

/// ステータスバーを消せなかった理由
public enum HideFailure: String, Sendable, Equatable, CaseIterable {
    /// カタログに無い大きさ（切り抜いた画像・SNS で縮んだ画像・iPhone 以外の画像など）
    case unknownSize
    /// 大きさは分かるが、自動判定の対象にしていない機種（iPhone Duo など）
    case unsupportedScreen
    /// 機種と iOS の世代を 1 つに決められなかった、または消す文字・アイコンが見つからなかった
    case undetermined
}

/// 消したステータスバーの情報
public struct HiddenStatusBar: Sendable, Equatable {
    /// 判定した配置（機種グループ × iOS の世代）
    public let layout: StatusBarLayout
    /// 背景の種類
    public let background: BackgroundKind
    /// ステータスバーの帯の高さ（px。画像の上端から）。画面で帯に印を付けるのに使う
    public let bandHeight: Int
    /// 消した跡が残りそうか。背景が写真・模様（`complex`）のときと、
    /// 建物の縁のような輪郭が文字・アイコンの後ろを通っているとき（背景の種類はグラデーションでも）に `true`
    public let mayLeaveTraces: Bool

    public init(layout: StatusBarLayout, background: BackgroundKind, bandHeight: Int, mayLeaveTraces: Bool) {
        self.layout = layout
        self.background = background
        self.bandHeight = bandHeight
        self.mayLeaveTraces = mayLeaveTraces
    }
}

public enum HideOutcome: Sendable, Equatable {
    case hidden(HiddenStatusBar)
    /// 消せなかった。画像は元のまま
    case notHidden(HideFailure)
}

/// 「隠す」の結果
public struct HideResult: Sendable {
    /// 元の画像
    public let original: CGImage
    /// 表示・書き出しに使う画像。消せなかったときは元の画像と同じ
    public let image: CGImage
    public let outcome: HideOutcome

    public init(original: CGImage, image: CGImage, outcome: HideOutcome) {
        self.original = original
        self.image = image
        self.outcome = outcome
    }

    /// 消せたときの情報
    public var hidden: HiddenStatusBar? {
        if case let .hidden(hidden) = outcome { return hidden }
        return nil
    }
}
