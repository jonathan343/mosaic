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

        let moviesCard = collectionCard(named: "Movies", in: app)
        XCTAssertTrue(moviesCard.waitForExistence(timeout: 5))

        app.buttons["Edit"].tap()
        app.buttons["deleteCollection.Movies"].tap()

        let deleteAlert = app.alerts["Delete Collection?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 2))
        XCTAssertTrue(deleteAlert.staticTexts["\"Movies\" and all of its tiles will be permanently deleted."].exists)

        deleteAlert.buttons["Cancel"].tap()
        XCTAssertTrue(moviesCard.waitForExistence(timeout: 2))

        app.buttons["deleteCollection.Movies"].tap()

        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 2))
        deleteAlert.buttons["Delete"].tap()

        XCTAssertFalse(moviesCard.waitForExistence(timeout: 2))
    }

    @MainActor
    func testCollectionNavigatesInNormalModeButNotInEditMode() throws {
        let app = makeApp()
        app.launch()

        let moviesCard = collectionCard(named: "Movies", in: app)
        XCTAssertTrue(moviesCard.waitForExistence(timeout: 5))

        moviesCard.tap()
        XCTAssertTrue(app.navigationBars["Movies"].waitForExistence(timeout: 2))

        app.navigationBars["Movies"].buttons.firstMatch.tap()
        XCTAssertTrue(moviesCard.waitForExistence(timeout: 2))

        app.buttons["Edit"].tap()
        moviesCard.tap()

        XCTAssertFalse(app.navigationBars["Movies"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testEditModeDragReordersCollections() throws {
        let app = makeApp()
        app.launch()

        let grid = app.scrollViews["collectionGrid"]
        let moviesCard = collectionCard(named: "Movies", in: app)
        let booksCard = collectionCard(named: "Books", in: app)

        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(moviesCard.waitForExistence(timeout: 5))
        XCTAssertTrue(booksCard.waitForExistence(timeout: 5))

        XCTAssertEqual(grid.value as? String, "Movies|TV Shows|Books|Albums")

        app.buttons["Edit"].tap()
        moviesCard.press(forDuration: 0.15, thenDragTo: booksCard)

        XCTAssertEqual(grid.value as? String, "TV Shows|Books|Movies|Albums")
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

    private func collectionCard(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["collectionCard.\(name)"]
    }
}
