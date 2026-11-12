import XCTest

/// 写真の選択から写真への保存までを、iOS が出す画面（写真の選択・許可の確認）も含めて通す。
///
/// Simulator の写真ライブラリに、ステータスバーが写ったスクリーンショットが入っている必要があるので、ふだんは動かさない（CI でも飛ばす）。
/// 動かすときは、スクリーンショットを `xcrun simctl addmedia <udid> <画像>` で入れてから、各画面の画像の出力先を渡す:
///
///     TEST_RUNNER_BARLESS_E2E_DIR=<出力先> xcodebuild test … -only-testing:BarlessUITests/PhotoFlowUITests
///
/// 選ぶ写真は、写真の選択の画面の左上から数えた番号で変えられる（`TEST_RUNNER_BARLESS_E2E_INDEX`。既定は 0）。
/// 保存した画像は写真ライブラリの先頭に入るので、2 回目からは番号が 1 つずつずれる
final class PhotoFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 写真の選択 → 「隠す」の結果 → 書き出し → 写真に保存 → ホームへ戻る
    @MainActor
    func testPickHideAndSave() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["BARLESS_E2E_DIR"] else {
            throw XCTSkip("BARLESS_E2E_DIR を渡したときだけ動かす")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        // 起動テストが横向きでも流れるので、その後に動かすと横向きのまま残っていることがある
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["home.pick"].waitForExistence(timeout: 10))
        try capture("01-home", to: output)

        app.buttons["home.pick"].tap()
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 15))
        let index = environment["BARLESS_E2E_INDEX"].flatMap(Int.init) ?? 0
        try XCTSkipIf(photos.count <= index, "写真ライブラリに写真が \(index + 1) 枚以上要る")
        try capture("02-picker", to: output)
        // 写真の選択は別のプロセスが描くので、要素としては押せない。画面の位置で押す
        photos.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.descendants(matching: .any)["editor.detected"].waitForExistence(timeout: 30))
        try capture("03-editor", to: output)
        // 押している間だけ元の画像が出て、離すと戻る
        app.descendants(matching: .any)["editor.canvas"].press(forDuration: 2)

        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["export.share"].waitForExistence(timeout: 30))
        try capture("04-export", to: output)

        app.buttons["export.save"].tap()
        // 初回は、写真への追加の許可を求められる。右のボタンが「許可」
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 8) {
            try capture("05-permission", to: output)
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        }
        XCTAssertTrue(app.buttons["export.done"].waitForExistence(timeout: 30))
        try capture("06-saved", to: output)

        app.buttons["export.done"].tap()
        XCTAssertTrue(app.buttons["home.pick"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func capture(_ name: String, to output: URL) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: output.appendingPathComponent("\(name).png"))
    }
}
