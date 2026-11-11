import Foundation

public enum DeviceCatalogError: Error, Equatable {
    case resourceNotFound
    case unsupportedSchema(Int)
}

/// 機種グループ × iOS の世代ごとの配置の一覧。
///
/// 中身は `Resources/device-catalog.json`（`Tools/statusbar/make-catalog.py` が実測から作る）。
/// 新しい機種・iOS には、撮り直して JSON を作り直すことで対応する。
public struct DeviceCatalog: Codable, Sendable {
    /// このコードが読める JSON の版
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    /// 実測を更新した日（YYYY-MM-DD）
    public let updatedAt: String
    public let unsupported: [UnsupportedScreen]
    public let layouts: [StatusBarLayout]

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(DeviceCatalog.self, from: data)
        guard catalog.schemaVersion == Self.supportedSchemaVersion else {
            throw DeviceCatalogError.unsupportedSchema(catalog.schemaVersion)
        }
        self = catalog
    }

    /// アプリに同梱したカタログを読む
    public static func bundled() throws -> DeviceCatalog {
        guard let url = Bundle.module.url(forResource: "device-catalog", withExtension: "json") else {
            throw DeviceCatalogError.resourceNotFound
        }
        return try DeviceCatalog(data: Data(contentsOf: url))
    }

    /// スクリーンショットの大きさ（px）が一致する配置。大きさだけでは 1 つに決まらないことがある
    public func candidates(pixelWidth: Int, pixelHeight: Int) -> [StatusBarLayout] {
        layouts.filter { $0.pixelWidth == pixelWidth && $0.pixelHeight == pixelHeight }
    }

    /// 自動判定の対象にしていない大きさなら、その情報を返す
    public func unsupportedScreen(pixelWidth: Int, pixelHeight: Int) -> UnsupportedScreen? {
        unsupported.first { $0.pixelWidth == pixelWidth && $0.pixelHeight == pixelHeight }
    }

    public func layout(id: String) -> StatusBarLayout? {
        layouts.first { $0.id == id }
    }
}
