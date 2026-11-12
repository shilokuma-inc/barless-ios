import Foundation

/// 画素単位の矩形（左上が原点）
public struct PixelRect: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var midX: Double { Double(x) + Double(width) / 2 }
    public var midY: Double { Double(y) + Double(height) / 2 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// 外側に広げる（負の値で縮める）
    public func insetBy(dx: Int, dy: Int) -> PixelRect {
        PixelRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    public func union(_ other: PixelRect) -> PixelRect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        return PixelRect(x: minX, y: minY, width: max(maxX, other.maxX) - minX, height: max(maxY, other.maxY) - minY)
    }

    public func intersection(_ other: PixelRect) -> PixelRect {
        let minX = max(x, other.x)
        let minY = max(y, other.y)
        return PixelRect(x: minX, y: minY, width: max(0, min(maxX, other.maxX) - minX), height: max(0, min(maxY, other.maxY) - minY))
    }

    /// 4 辺それぞれの差の最大値（px）。配置がどれだけずれているかの目安に使う
    public func maxEdgeDistance(to other: PixelRect) -> Int {
        max(abs(x - other.x), abs(y - other.y), abs(maxX - other.maxX), abs(maxY - other.maxY))
    }
}

/// ステータスバーの見た目が変わる iOS の世代。iOS 18 と 26 は同じ配置で、27 で位置・大きさ・アイコンの形が変わった（docs/device-table.md）
public enum OSGeneration: String, Codable, Sendable, CaseIterable {
    case iOS18to26 = "ios18-26"
    case iOS27 = "ios27"
}

/// 要素の並び方
public enum StatusBarStyle: String, Codable, Sendable {
    /// 時刻が左、電波・Wi-Fi・電池が右（ノッチ・Dynamic Island の機種）
    case leadingTime
    /// 時刻が中央、電波・キャリア名・Wi-Fi が左、電池が右（ホームボタンの機種）
    case centeredTime
}

/// 実測した時刻の位置。文字列によって幅が変わるので、撮ったときの文字列と組で持つ
public struct TimeSample: Codable, Hashable, Sendable {
    public let text: String
    /// 文字が実際に描かれている範囲（px）
    public let ink: PixelRect

    public init(text: String, ink: PixelRect) {
        self.text = text
        self.ink = ink
    }
}

/// 行の範囲（px）。`bottom` は含まない
public struct RowRange: Codable, Hashable, Sendable {
    public let top: Int
    public let bottom: Int

    public init(top: Int, bottom: Int) {
        self.top = top
        self.bottom = bottom
    }
}

/// 「機種グループ × iOS の世代」ごとのステータスバーの配置。単位は px
public struct StatusBarLayout: Codable, Hashable, Sendable, Identifiable {
    /// 例: `1206x2622-a/ios27`
    public let id: String
    /// 機種グループ。同じ大きさでも配置が違う機種は別のグループになる（例: `1206x2622-a` と `1206x2622-b`）
    public let group: String
    /// このグループで実測した機種
    public let models: [String]
    public let generation: OSGeneration
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// 1pt あたりの px
    public let scale: Int
    /// 画面の大きさ（対角のインチ）。画面に「6.3 インチ」のように出すのに使う。
    /// 機種名（`models`）は実測した機種だけなので、利用者には見せない
    public let screenInches: Double
    public let style: StatusBarStyle
    /// 文字とアイコンが描かれている範囲の上端と下端（px）
    public let inkTop: Int
    public let inkBottom: Int
    public let timeSamples: [TimeSample]
    public let cellular: PixelRect
    public let wifi: PixelRect
    public let battery: PixelRect
    /// キャリア名（ホームボタンの機種だけ）
    public let carrier: PixelRect?
    /// 電波の棒 4 本（左から）
    public let cellularBars: [PixelRect]
    /// Wi-Fi の 3 つの帯を、中央の列で測った行の範囲（上から。いちばん下が扇形の根元）
    public let wifiBands: [RowRange]
    /// 電池の本体（突起を除く）
    public let batteryBody: PixelRect
    /// 電池の右端の突起
    public let batteryNub: PixelRect
    /// 実測の元（`<機種>__<ランタイム>`。`docs/device-table.json` のキーと同じ形）
    public let sources: [String]

    /// 右側（`centeredTime` では時刻以外）のアイコンをすべて含む範囲
    public var iconsBounds: PixelRect {
        [wifi, battery, carrier].compactMap { $0 }.reduce(cellular) { $0.union($1) }
    }
}

/// 自動判定の対象にしていない大きさ
public struct UnsupportedScreen: Codable, Hashable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let models: [String]
    /// 理由。`vertical-layout` は、時刻などが上端に横 1 列で並ばない配置（iPhone Duo）
    public let reason: String
}
