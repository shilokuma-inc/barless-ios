import Foundation

/// 文字とアイコンの色
public enum ContentAppearance: String, Sendable, Equatable, CaseIterable {
    /// 黒い文字・アイコン（明るい背景）
    case darkContent
    /// 白い文字・アイコン（暗い背景）
    case lightContent
}

/// 電池の表示
public struct BatterySpec: Sendable, Equatable {
    public enum State: String, Sendable, Equatable, CaseIterable {
        case normal
        /// 充電中（緑 + 稲妻のマーク）
        case charging
        /// 低電力モード（黄）
        case lowPower
    }

    /// これ以下の残量は赤で描く
    public static let lowLevelThreshold = 0.2

    /// 残量（0〜1）
    public var level: Double
    public var state: State

    public init(level: Double, state: State = .normal) {
        self.level = min(max(level, 0), 1)
        self.state = state
    }
}

/// 描き直すステータスバーの中身。`nil` の要素は描かない
public struct StatusBarSpec: Sendable, Equatable {
    /// 時刻の文字列（例: `9:41`）
    public var time: String?
    /// 電波の本数（0〜4）
    public var cellularBars: Int?
    /// Wi-Fi の本数（0〜3）
    public var wifiBars: Int?
    public var battery: BatterySpec?

    public init(time: String? = nil, cellularBars: Int? = nil, wifiBars: Int? = nil, battery: BatterySpec? = nil) {
        self.time = time
        self.cellularBars = cellularBars
        self.wifiBars = wifiBars
        self.battery = battery
    }

    /// 「整える」モードの標準の値（9:41・電波最大・Wi-Fi 最大・電池満タン）
    public static let tidy = StatusBarSpec(time: "9:41", cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: 1))
}
