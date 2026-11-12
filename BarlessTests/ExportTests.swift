@testable import Barless
import CoreGraphics
import Foundation
import ImageIOKit
import Testing

/// 書き出しの状態と、書き出すファイル
@MainActor
struct ExportModelTests {
    /// 渡されたファイルを覚えておき、指定があればエラーを返す
    private actor StubSaver: PhotoSaving {
        private(set) var savedURLs: [URL] = []
        private let error: (any Error)?

        init(error: (any Error)? = nil) {
            self.error = error
        }

        func save(imageAt url: URL) async throws {
            if let error { throw error }
            savedURLs.append(url)
        }
    }

    private func image() throws -> CGImage {
        try Bitmap(width: 30, height: 60, fill: RGB(red: 20, green: 120, blue: 220)).makeCGImage()
    }

    /// Software 欄にアプリ名が入り、位置情報は入らない（仕様書 §5-4a）
    @Test
    func preparesPNGWithSoftwareName() async throws {
        let model = ExportModel(image: try image(), saver: StubSaver())

        await model.prepare()

        let url = try #require(model.fileURL)
        #expect(url.pathExtension == "png")
        let data = try Data(contentsOf: url)
        #expect(ImageMetadata.softwareName(of: data) == "Barless")
        #expect(!ImageMetadata.hasLocation(data))
        let restored = try Bitmap(cgImage: ImageDecoder.decode(data: data))
        #expect(restored[10, 10] == RGB(red: 20, green: 120, blue: 220))
    }

    @Test
    func savesPreparedFile() async throws {
        let saver = StubSaver()
        let model = ExportModel(image: try image(), saver: saver)
        await model.prepare()

        await model.save()

        #expect(model.saveState == .saved)
        #expect(model.problem == nil)
        #expect(await saver.savedURLs == [try #require(model.fileURL)])
    }

    /// ファイルの用意ができる前や、保存済みの後に押されても、保存しない
    @Test
    func savesOnlyOncePerFile() async throws {
        let saver = StubSaver()
        let model = ExportModel(image: try image(), saver: saver)

        await model.save()
        #expect(model.saveState == .idle)

        await model.prepare()
        await model.save()
        await model.save()

        #expect(await saver.savedURLs.count == 1)
    }

    @Test
    func reportsDeniedPermission() async throws {
        let model = ExportModel(image: try image(), saver: StubSaver(error: PhotoSaveError.notAuthorized))
        await model.prepare()

        await model.save()

        #expect(model.saveState == .idle)
        #expect(model.problem == .notAuthorized)
    }

    @Test
    func reportsSaveFailure() async throws {
        let model = ExportModel(image: try image(), saver: StubSaver(error: CocoaError(.fileWriteUnknown)))
        await model.prepare()

        await model.save()

        #expect(model.saveState == .idle)
        #expect(model.problem == .failed)
    }

    /// 形式を変えると、その形式のファイルを作り直し、保存済みの印を戻す
    @Test
    func changingFormatPreparesNewFile() async throws {
        let model = ExportModel(image: try image(), saver: StubSaver())
        await model.prepare()
        await model.save()

        model.format = .heic
        await model.prepare()

        #expect(model.saveState == .idle)
        let url = try #require(model.fileURL)
        #expect(url.pathExtension == "heic")
        let data = try Data(contentsOf: url)
        #expect(ImageMetadata.softwareName(of: data) == "Barless")
    }

    @Test
    func reportsPreparationFailure() async throws {
        let model = ExportModel(image: try image(), saver: StubSaver()) { _, _ in
            throw ImageCodecError.cannotEncode
        }

        await model.prepare()

        #expect(model.preparation == .failed)
        #expect(model.fileURL == nil)
    }
}

struct ExportFileTests {
    @Test
    func namesFileWithDateAndFormat() throws {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 11, 12)
        (components.hour, components.minute, components.second) = (18, 52, 3)
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))

        #expect(ExportFile.fileName(format: .png, date: date) == "Barless-20261112-185203.png")
        #expect(ExportFile.fileName(format: .heic, date: date) == "Barless-20261112-185203.heic")
    }
}

struct LocalizationTests {
    /// 文言のカタログがアプリに入っていて、日本語が引ける（置き換えのある文言も含めて）
    @Test(arguments: [
        ("Choose a screenshot", "スクショを選ぶ"),
        ("Save to Photos", "写真に保存"),
        ("Detected as %@ size · %@", "%1$@ 相当・%2$@ として認識"),
        ("iOS 18–26", "iOS 18〜26")
    ])
    func japaneseStringsAreBundled(key: String, expected: String) throws {
        let path = try #require(Bundle.main.path(forResource: "ja", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    /// 写真への追加の許可を求める文言が入っている
    @Test
    func photoLibraryUsageDescriptionExists() throws {
        let text = try #require(Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String)
        #expect(!text.isEmpty)
    }
}
