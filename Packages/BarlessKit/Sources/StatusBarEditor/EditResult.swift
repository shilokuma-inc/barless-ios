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

/// 編集の結果。「隠す」と「整える」の画像と、「遊ぶ」で描き直すための入れ物を持つ
public struct EditResult: Sendable {
    /// 元の画像
    public let original: CGImage
    /// 「隠す」: ステータスバーを消した画像。消せなかったときは元の画像と同じ
    public let hidden: CGImage
    /// 「整える」: 消したうえで、定番の表示に描き直した画像。消せなかったときは `nil`
    public let tidied: CGImage?
    public let outcome: HideOutcome
    /// 「遊ぶ」: 中身を変えて描き直すための入れ物。消せなかったときは `nil`
    public let composer: StatusBarComposer?

    public init(original: CGImage, hidden: CGImage, tidied: CGImage?, outcome: HideOutcome, composer: StatusBarComposer? = nil) {
        self.original = original
        self.hidden = hidden
        self.tidied = tidied
        self.outcome = outcome
        self.composer = composer
    }

    /// 消せたときの情報
    public var statusBar: HiddenStatusBar? {
        if case let .hidden(statusBar) = outcome { return statusBar }
        return nil
    }
}
