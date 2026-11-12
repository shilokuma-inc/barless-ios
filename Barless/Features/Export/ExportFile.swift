import CoreGraphics
import Foundation
import ImageIOKit

/// 書き出す画像のファイル。保存と共有の両方で、同じファイルを使う
nonisolated enum ExportFile {
    /// メタデータの Software 欄に書くアプリ名（仕様書 §5-4a）
    static let softwareName = "Barless"

    /// 一時フォルダの中の、書き出し用のフォルダ
    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
    }

    /// 画像を `format` の形式でファイルに書く。
    ///
    /// 書き出しごとに別のフォルダへ書く。形式を切り替えた直後は 2 つの書き出しが同時に進むことがあり、
    /// 同じ場所を使うと、遅れて終わったほうが、使っている最中のファイルを消してしまうため。
    /// 画素から作り直すので、元の画像の位置情報や撮影日時は入らない。メインスレッドの外で動く
    @concurrent
    static func write(
        _ image: CGImage,
        format: ImageFileFormat,
        in directory: URL = defaultDirectory,
        date: Date = Date()
    ) async throws -> URL {
        let data = try ImageEncoder.encode(image, options: ExportOptions(format: format, softwareName: softwareName))
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(format: format, date: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 前の書き出しで残ったファイルをすべて消す。書き出しの画面を開いたときに、新しく書く前に呼ぶ
    @concurrent
    static func removeAll(in directory: URL = defaultDirectory) async {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 使わなかった書き出しのファイルを、フォルダごと消す
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// `Barless-20261112-185203.png` の形のファイル名
    static func fileName(format: ImageFileFormat, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(softwareName)-\(formatter.string(from: date)).\(format.rawValue)"
    }
}
