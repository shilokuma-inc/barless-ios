import CoreGraphics
import Foundation
import ImageIOKit
import os

/// 書き出す画像のファイル。保存と共有の両方で、同じファイルを使う
nonisolated enum ExportFile {
    /// メタデータの Software 欄に書くアプリ名（仕様書 §5-4a）
    static let softwareName = "Barless"

    /// 保存の途中のファイルが入っているフォルダの名前。片付けでは消さない
    private static let foldersInUse = OSAllocatedUnfairLock(initialState: Set<String>())

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

    /// 前の書き出しで残ったファイルを消す。書き出しの画面を開いたときに、新しく書く前に呼ぶ。
    ///
    /// 保存の途中のファイル（`beginUsing` から `endUsing` の間）は残す。保存を始めてすぐ画面を戻り、
    /// 書き出しの画面を開き直したときに、保存しているファイルを消さないため
    @concurrent
    static func removeAll(in directory: URL = defaultDirectory) async {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let inUse = foldersInUse.withLock { $0 }
        for folder in folders where !inUse.contains(folder) {
            try? manager.removeItem(at: directory.appendingPathComponent(folder))
        }
    }

    /// そのファイルを使い始める（片付けの対象から外す）
    static func beginUsing(_ url: URL) {
        _ = foldersInUse.withLock { $0.insert(folderName(of: url)) }
    }

    /// そのファイルを使い終えた（次の片付けで消してよい）
    static func endUsing(_ url: URL) {
        _ = foldersInUse.withLock { $0.remove(folderName(of: url)) }
    }

    /// 書き出しごとのフォルダの名前（UUID なので、置き場所が違っても重ならない）
    private static func folderName(of url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent
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
