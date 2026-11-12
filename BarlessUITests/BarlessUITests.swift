//
//  BarlessUITests.swift
//  BarlessUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class BarlessUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsHome() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["home.pick"].waitForExistence(timeout: 10))
    }

    /// 作り物のスクリーンショットで、「整える」に切り替え、比較を出し、そのまま書き出しへ進める
    @MainActor
    func testSampleScreenshotCanBeTidiedAndCompared() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-screenshot-demo", "-screenshot-scene", "editor"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["editor.detected"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["editor.tidySummary"].exists)

        app.buttons["editor.mode.tidy"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.tidySummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.mode.tidy"].isSelected)

        app.buttons["editor.compare"].tap()
        XCTAssertTrue(app.buttons["editor.compare"].isSelected)

        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["export.share"].waitForExistence(timeout: 30))
        // 戻っても、選んだモードと比較はそのまま
        app.buttons["edit.back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.tidySummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editor.compare"].isSelected)
    }

    /// 作り物のスクリーンショットで、「隠す」の結果 → 書き出し → 編集へ戻る → ホームへ戻る、を通す。
    /// 写真の選択と写真への保存は iOS の画面なので、ここでは通さない
    @MainActor
    func testSampleScreenshotGoesThroughEditorAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-screenshot-demo", "-screenshot-scene", "editor"]
        app.launch()

        // 解析が終わると、判定の結果が出る
        XCTAssertTrue(app.descendants(matching: .any)["editor.detected"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["editor.traces"].exists)

        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["export.save"].waitForExistence(timeout: 10))
        // ファイルの用意ができると、共有のボタンが出る
        XCTAssertTrue(app.descendants(matching: .any)["export.share"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["export.save"].isEnabled)

        app.buttons["edit.back"].tap()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 10))

        app.buttons["edit.close"].tap()
        XCTAssertTrue(app.buttons["home.pick"].waitForExistence(timeout: 10))
    }
}
