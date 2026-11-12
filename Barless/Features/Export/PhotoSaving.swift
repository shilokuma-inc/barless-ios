import Foundation
import Photos

nonisolated enum PhotoSaveError: Error, Equatable {
    /// 写真への追加が許可されていない
    case notAuthorized
}

/// 画像のファイルを写真ライブラリに保存する処理。画面のテストで差し替えられるようにしている
nonisolated protocol PhotoSaving: Sendable {
    func save(imageAt url: URL) async throws
}

/// 写真ライブラリへ追加する。求めるのは「追加のみ」の権限で、ライブラリの中身は読まない
nonisolated struct PhotoLibrarySaver: PhotoSaving {
    func save(imageAt url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoSaveError.notAuthorized }
        // UIImage を経由せずにファイルのまま渡す。形式（PNG / HEIC）とメタデータがそのまま保存される
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}
