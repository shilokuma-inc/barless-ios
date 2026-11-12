import CoreGraphics
import Foundation
import ImageIOKit

/// 書き出す画像のファイル。保存と共有の両方で、同じファイルを使う
nonisolated enum ExportFile {
    /// メタデータの Software 欄に書くアプリ名（仕様書 §5-4a）
    static let softwareName = "Barless"

    /// 一時フォルダの中の、書き出し用のフォルダ
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
    }

    /// 画像を `format` の形式でファイルに書く。前に書いたファイルは消す。
    ///
    /// 画素から作り直すので、元の画像の位置情報や撮影日時は入らない。メインスレッドの外で動く
    @concurrent
    static func write(_ image: CGImage, format: ImageFileFormat, date: Date = Date()) async throws -> URL {
        let data = try ImageEncoder.encode(image, options: ExportOptions(format: format, softwareName: softwareName))
        let manager = FileManager.default
        let directory = directory
        try? manager.removeItem(at: directory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(format: format, date: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// `Barless-20261112-185203.png` の形のファイル名
    static func fileName(format: ImageFileFormat, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(softwareName)-\(formatter.string(from: date)).\(format.rawValue)"
    }
}
