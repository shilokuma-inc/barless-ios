import Foundation
import ImageIOKit

/// テスト用の画像 1 枚。Simulator・実機で撮ったスクリーンショットの上端だけを切り出したもの
/// （作り方は `Tools/statusbar/make-fixtures.py`）
public struct Fixture: Codable, Sendable, CustomStringConvertible {
    /// `Fixtures/` からの相対パス
    public let file: String
    /// `simulator` か `device`（実機）
    public let source: String
    public let device: String
    public let runtime: String
    /// `light-full` / `light-low` / `dark-full` / `dark-home`（実機は `light-real` / `dark-real`）
    public let variant: String
    /// 切り出す前のスクリーンショットの大きさ（px）
    public let width: Int
    public let height: Int
    public let scale: Int
    /// `light`（黒い文字）か `dark`（白い文字）
    public let appearance: String
    /// `solid`（設定アプリ。単色）か `wallpaper`（ホーム画面）
    public let background: String
    public let time: String
    public let cellularBars: Int?
    public let wifiBars: Int?
    public let batteryLevel: Int?
    public let batteryState: String?

    public var name: String {
        URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    }

    public var description: String { name }

    /// 配置の世代（`ios18-26` か `ios27`）。`DeviceCatalog` の `OSGeneration` の rawValue と同じ
    public var generationID: String {
        runtime.hasPrefix("iOS-27") ? "ios27" : "ios18-26"
    }

    public var isSolidBackground: Bool { background == "solid" }

    /// 上端の切り出しを読み込む
    public func loadStrip() throws -> Bitmap {
        let url = try Fixtures.directory().appendingPathComponent(file)
        return try Bitmap(cgImage: ImageDecoder.decode(contentsOf: url))
    }
}

public enum FixtureError: Error {
    case directoryNotFound
}

public enum Fixtures {
    private struct Manifest: Codable {
        let stripHeightPt: Int
        let fixtures: [Fixture]
    }

    static func directory() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw FixtureError.directoryNotFound
        }
        return url
    }

    /// すべての画像（`manifest.json` の順）
    public static func all() throws -> [Fixture] {
        let data = try Data(contentsOf: directory().appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(Manifest.self, from: data).fixtures
    }

    /// 配置が「上端に横 1 列」で、自動判定の対象にしている画像（iPhone Duo を除く）
    public static func supported() throws -> [Fixture] {
        try all().filter { $0.device != "iPhone-Duo" }
    }
}
