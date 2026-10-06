import XCTest

/// Deep links opened through the system, exactly as from Safari, another app or a notification.
final class DeepLinkUITests: WaypointUITestCase {
    func testLinkOpenedFromInsideTheApp() {
        launch()
        tapTab("Profile")
        tap("profile.links")

        tap("link.waypoint://feed/photo/3")
        confirmOpenIfAsked()

        XCTAssertTrue(app.navigationBars["Leaf"].waitForExistence(timeout: 8))
    }

    func testAlbumLinkSelectsTheAlbumAndPushesThePhoto() {
        launch()

        openLink("waypoint://albums/sky/photo/7")

        XCTAssertTrue(app.navigationBars["Camera"].waitForExistence(timeout: 8))
    }

    func testColorLinkAwaitsThePickerAndSavesTheResult() {
        launch()

        openLink("waypoint://profile/color")
        tap("color.teal")

        let avatar = app.descendants(matching: .any)["profile.color"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        let saved = expectation(for: NSPredicate(format: "label == %@", "Favorite color Teal"), evaluatedWith: avatar)
        wait(for: [saved], timeout: 5)
    }

    func testLinkAsksBeforeDiscardingAnUnsavedDraft() {
        launch()
        tapTab("Explore")
        tap("lab.editor")
        tap("editor.text")
        app.typeText("draft")

        // Keep editing: the link is dropped and the draft stays.
        openLink("waypoint://feed/photo/3")
        let keep = app.alerts.buttons["Keep editing"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 3))

        // Discard: the draft goes and the link opens.
        openLink("waypoint://feed/photo/3")
        let discard = app.alerts.buttons["Discard and open"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.navigationBars["Leaf"].waitForExistence(timeout: 8))
    }

    func testNotificationTapTakesTheSamePath() {
        launch()
        tapTab("Profile")
        tap("profile.links")

        tap("link.notification")
        confirmOpenIfAsked()

        XCTAssertTrue(app.navigationBars["Tram"].waitForExistence(timeout: 8))
    }

    private func openLink(_ link: String) {
        XCUIDevice.shared.system.open(URL(string: link)!)
        confirmOpenIfAsked()
    }

    /// The system may ask before opening a URL.
    private func confirmOpenIfAsked() {
        let openButton = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if openButton.waitForExistence(timeout: 2) { openButton.tap() }
    }
}

/// Split view, popovers and sheet sizing. They run on iPhone too, where the split view collapses into a stack
/// and popovers adapt to sheets, and every flow must still free what it created.
final class AdaptiveUITests: WaypointUITestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testSplitViewSelectionFreesThePreviousAlbum() {
        launch()
        tapTab("Albums")
        if isPad {
            // An album is selected at launch on iPad. Switching albums replaces its flow; nothing piles up.
            waitFor("feed.photo.4")
            let baseline = settledCounts()

            tap("album.city")
            tap("feed.photo.1")
            waitFor("detail.hero")
            screenshot("split-ipad")
            tap("album.landscapes")

            waitFor("feed.photo.4")
            assertReturns(to: baseline)
        } else {
            // Collapsed: picking an album pushes it, and going back clears the selection and frees the flow.
            // SwiftUI keeps the last popped detail of a collapsed split view until the next selection (as a
            // NavigationStack keeps its last popped screen), so visit a second album: nothing may pile up.
            waitFor("album.sky")
            let baseline = settledCounts()

            tap("album.sky")
            tap("feed.photo.3")
            waitFor("detail.hero")
            tapBack()
            waitFor("feed.photo.3")
            tapBack()
            waitFor("album.city")
            tap("album.city")
            waitFor("feed.photo.1")
            tapBack()

            waitFor("album.sky")
            assertReturns(to: baseline)
        }
    }

    func testPopoverAdaptsAndFreesWhenDismissed() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.popover")
        waitFor("popoverInfo")
        screenshot("popover-adaptive")
        dismissPopoverOrSheet(isPopover: isPad)

        waitForDisappearance("popoverInfo")
        assertReturns(to: baseline)
    }

    func testPopoverEverywhereFreesWhenDismissed() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.popoverEverywhere")
        waitFor("popoverInfo")
        dismissPopoverOrSheet(isPopover: true)

        waitForDisappearance("popoverInfo")
        assertReturns(to: baseline)
    }

    func testSizedSheetsFreeOnClose() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        for demo in ["form", "page", "fitted"] {
            tap("lab.sizing.\(demo)")
            waitFor("sizedSheet")
            screenshot("sizing-\(demo)")
            tap("close")
            waitForDisappearance("sizedSheet")
        }

        assertReturns(to: baseline)
    }

    /// A popover dismisses with a tap outside it; a sheet with a swipe down.
    private func dismissPopoverOrSheet(isPopover: Bool) {
        let window = app.windows.firstMatch.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        if isPopover {
            let info = app.descendants(matching: .any)["popoverInfo"].firstMatch.frame
            let x = info.midX < window.midX ? window.maxX - 40 : window.minX + 40
            origin.withOffset(CGVector(dx: x, dy: window.maxY - 140)).tap()
        } else {
            let grab = origin.withOffset(CGVector(dx: window.midX, dy: window.height * 0.53))
            grab.press(forDuration: 0.1, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: window.height * 0.45)))
        }
    }
}
