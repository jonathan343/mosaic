//
//  MosaicUITests.swift
//  MosaicUITests
//
//  Created by Jonathan Gaytan on 3/21/26.
//

import XCTest

final class MosaicUITests: XCTestCase {
    private let uiTestingLaunchArgument = "UI_TESTING"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExample() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testDeletingCollectionRequiresConfirmation() throws {
        let app = makeApp()
        app.launch()

        let moviesLabel = app.staticTexts["Movies"]
        XCTAssertTrue(moviesLabel.waitForExistence(timeout: 5))

        moviesLabel.swipeLeft()
        app.buttons["Delete"].tap()

        let deleteAlert = app.alerts["Delete Collection?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 2))
        XCTAssertTrue(deleteAlert.staticTexts["\"Movies\" and all of its tiles will be permanently deleted."].exists)

        deleteAlert.buttons["Cancel"].tap()
        XCTAssertTrue(moviesLabel.waitForExistence(timeout: 2))

        moviesLabel.swipeLeft()
        app.buttons["Delete"].tap()

        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 2))
        deleteAlert.buttons["Delete"].tap()

        XCTAssertFalse(moviesLabel.waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(uiTestingLaunchArgument)
        return app
    }
}
