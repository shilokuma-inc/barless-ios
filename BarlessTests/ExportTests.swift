@testable import Barless
import CoreGraphics
import Foundation
import ImageIOKit
import os
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

    /// 開けるまで待たせる門（書き出しが終わる順を、テストから決めるために使う）
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    /// 保存を、テストが合図するまで待たせる。合図の後にファイルが無ければ失敗する
    private actor SlowSaver: PhotoSaving {
        let started = Gate()
        let release = Gate()

        func save(imageAt url: URL) async throws {
            await started.open()
            await release.wait()
            guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        }
    }

    private func image() throws -> CGImage {
        try Bitmap(width: 30, height: 60, fill: RGB(red: 20, green: 120, blue: 220)).makeCGImage()
    }

    /// テストごとに別の書き出し先（テストは並んで走るので、同じ場所を使うと互いのファイルを消してしまう）
    private func model(
        saver: any PhotoSaving = StubSaver(),
        directory: URL? = nil,
        writer: ExportModel.Writer? = nil
    ) throws -> ExportModel {
        ExportModel(image: try image(), saver: saver, directory: directory ?? Self.temporaryDirectory(), writer: writer)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ExportTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// 保存か共有をしたことは、最初の 1 回だけ知らせる（保存してから共有しても、1 回と数える）。保存に失敗したときは知らせない
    @Test
    func reportsFirstExportOnce() async throws {
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let failing = try model(saver: StubSaver(error: PhotoSaveError.notAuthorized))
        failing.onFirstExport = { counter.withLock { $0 += 1 } }
        await failing.prepare()
        await failing.save()
        #expect(!failing.hasExported)
        #expect(counter.withLock { $0 } == 0)

        let model = try model()
        model.onFirstExport = { counter.withLock { $0 += 1 } }
        await model.prepare()
        await model.save()
        #expect(model.saveState == .saved && model.hasExported)
        // 共有を押したとき
        model.noteExported()
        model.noteExported()

        #expect(counter.withLock { $0 } == 1)
    }

    /// Software 欄にアプリ名が入り、位置情報は入らない（仕様書 §5-4a）
    @Test
    func preparesPNGWithSoftwareName() async throws {
        let model = try model()

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
        let model = try model(saver: saver)
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
        let model = try model(saver: saver)

        await model.save()
        #expect(model.saveState == .idle)

        await model.prepare()
        await model.save()
        await model.save()

        #expect(await saver.savedURLs.count == 1)
    }

    @Test
    func reportsDeniedPermission() async throws {
        let model = try model(saver: StubSaver(error: PhotoSaveError.notAuthorized))
        await model.prepare()

        await model.save()

        #expect(model.saveState == .idle)
        #expect(model.problem == .notAuthorized)
    }

    @Test
    func reportsSaveFailure() async throws {
        let model = try model(saver: StubSaver(error: CocoaError(.fileWriteUnknown)))
        await model.prepare()

        await model.save()

        #expect(model.saveState == .idle)
        #expect(model.problem == .failed)
    }

    /// 形式を変えると、その形式のファイルを作り直し、保存済みの印を戻す
    @Test
    func changingFormatPreparesNewFile() async throws {
        let model = try model()
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

    /// 形式を切り替えた直後は 2 つの書き出しが同時に進む。前の形式が後から終わっても、使っているファイルは消えない
    @Test
    func keepsReadyFileWhenEarlierExportFinishesLater() async throws {
        let directory = Self.temporaryDirectory()
        let started = Gate()
        let release = Gate()
        let model = try model(directory: directory) { image, format in
            // PNG の書き出しだけを、HEIC が終わるまで待たせる
            if format == .png {
                await started.open()
                await release.wait()
            }
            return try await ExportFile.write(image, format: format, in: directory)
        }
        let earlier = Task { await model.prepare() }
        await started.wait()

        model.format = .heic
        await model.prepare()
        let ready = try #require(model.fileURL)
        #expect(ready.pathExtension == "heic")

        await release.open()
        await earlier.value

        #expect(model.fileURL == ready)
        #expect(FileManager.default.fileExists(atPath: ready.path))
        // 使われなかった PNG は残さない
        let folders = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(folders == [ready.deletingLastPathComponent().lastPathComponent])
    }

    /// 前の書き出しで残ったファイルは、新しく書く前に片付ける
    @Test
    func removesLeftoversBeforeFirstExport() async throws {
        let directory = Self.temporaryDirectory()
        let leftover = directory.appendingPathComponent("old/leftover.png")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: leftover)
        let model = try model(directory: directory)

        await model.prepare()

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: try #require(model.fileURL).path))
    }

    /// 保存を始めてすぐ画面を戻り、書き出しの画面を開き直しても、保存しているファイルは片付けで消えない
    @Test
    func keepsFileBeingSavedWhenExportReopens() async throws {
        let directory = Self.temporaryDirectory()
        let saver = SlowSaver()
        let first = try model(saver: saver, directory: directory)
        await first.prepare()
        let saving = try #require(first.fileURL)
        let save = Task { await first.save() }
        await saver.started.wait()

        // 開き直した画面が、同じ場所で片付けと用意を始める
        let second = try model(directory: directory)
        await second.prepare()
        #expect(FileManager.default.fileExists(atPath: saving.path))

        await saver.release.open()
        await save.value
        #expect(first.saveState == .saved)

        // 保存が済んだファイルは、次の片付けで消える
        let third = try model(directory: directory)
        await third.prepare()
        #expect(!FileManager.default.fileExists(atPath: saving.path))
    }

    @Test
    func reportsPreparationFailure() async throws {
        let model = try model { _, _ in
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

    /// 書き出しごとに別のフォルダへ書くので、後の書き出しが前のファイルを消さない
    @Test
    func writesEachExportToItsOwnFolder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExportTests-\(UUID().uuidString)", isDirectory: true)
        let image = try Bitmap(width: 8, height: 8).makeCGImage()

        let first = try await ExportFile.write(image, format: .png, in: directory)
        let second = try await ExportFile.write(image, format: .png, in: directory)

        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))

        await ExportFile.removeAll(in: directory)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }
}

struct LocalizationTests {
    /// 文言のカタログがアプリに入っていて、日本語が引ける（置き換えのある文言も含めて）
    @Test(arguments: [
        ("Choose a screenshot", "スクショを選ぶ"),
        ("Save to Photos", "写真に保存"),
        ("Detected as %@-inch · %@", "%1$@ インチ・%2$@ として認識"),
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
