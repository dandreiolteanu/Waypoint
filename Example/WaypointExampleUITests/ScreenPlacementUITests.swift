import XCTest

/// Every screen reads how it got on screen from `\.screenPlacement`, set by `NavigationHost`.
final class ScreenPlacementUITests: WaypointUITestCase {
    func testRootPushedSheetAndCoverPlacements() {
        launch()
        assertPlacement("grid", is: "root")

        tap("feed.photo.4")
        waitFor("detail.hero")
        assertPlacement("detail", is: "pushed")

        tap("detail.comments")
        assertPlacement("comments", is: "presented.sheet")
        tap("close")
        waitForDisappearance("close")

        tap("detail.hero")
        assertPlacement("viewer", is: "presented.fullScreenCover")
        tap("viewer.close")
        waitForDisappearance("viewer.close")
        assertPlacement("detail", is: "pushed")
    }

    private func assertPlacement(_ screen: String, is expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.descendants(matching: .any)["placement.\(screen)"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "No placement probe on \(screen)", file: file, line: line)
        XCTAssertEqual(probe.value as? String, expected, file: file, line: line)
    }
}
