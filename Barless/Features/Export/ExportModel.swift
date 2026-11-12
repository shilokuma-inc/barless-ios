import CoreGraphics
import Foundation
import ImageIOKit
import Observation

/// 書き出しの画面の状態
@MainActor
@Observable
final class ExportModel {
    /// 書き出すファイルの用意
    enum Preparation: Equatable {
        case preparing
        case ready(URL)
        case failed
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    /// 保存できなかった理由（お知らせに出す）
    enum SaveProblem: Equatable {
        case notAuthorized
        case failed
    }

    /// ファイルに書く処理（テストで差し替える）
    typealias Writer = @Sendable (CGImage, ImageFileFormat) async throws -> URL

    var format = ImageFileFormat.png
    private(set) var preparation = Preparation.preparing
    private(set) var saveState = SaveState.idle
    var problem: SaveProblem?

    private let image: CGImage
    private let saver: any PhotoSaving
    private let writer: Writer

    init(
        image: CGImage,
        saver: any PhotoSaving = PhotoLibrarySaver(),
        writer: @escaping Writer = { try await ExportFile.write($0, format: $1) }
    ) {
        self.image = image
        self.saver = saver
        self.writer = writer
    }

    /// 用意できたファイル
    var fileURL: URL? {
        if case let .ready(url) = preparation { return url }
        return nil
    }

    /// 今の形式でファイルを用意する。形式を変えたら呼び直す（保存済みの印も戻す）
    func prepare() async {
        let format = format
        preparation = .preparing
        saveState = .idle
        do {
            let url = try await writer(image, format)
            // 待っている間に形式が変わっていたら、新しいほうの結果に任せる
            guard format == self.format else { return }
            preparation = .ready(url)
        } catch {
            guard format == self.format else { return }
            preparation = .failed
        }
    }

    /// 写真ライブラリに保存する
    func save() async {
        guard let fileURL, saveState == .idle else { return }
        saveState = .saving
        do {
            try await saver.save(imageAt: fileURL)
            saveState = .saved
        } catch PhotoSaveError.notAuthorized {
            saveState = .idle
            problem = .notAuthorized
        } catch {
            saveState = .idle
            problem = .failed
        }
    }
}
