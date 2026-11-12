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
}
