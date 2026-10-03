import XCTest

/// Drives every flow in the example through real SwiftUI and checks that leaving a flow frees everything it created.
/// Every coordinator, navigator, screen entry and view model must be gone, including after swipe-back and swipe-down.
final class StackLifetimeUITests: WaypointUITestCase {
    func testPushAndBackButtonFreesScreen() {
        launch()
        let baseline = settledCounts()

        tap("feed.photo.1")
        waitFor("detail.hero")
        XCTAssertNotEqual(settledCounts(), baseline)
        tapBack()

        assertReturns(to: baseline)
    }

    func testZoomPushAndSwipeBackFreesScreen() {
        launch()
        let baseline = settledCounts()

        tap("feed.photo.2")
        waitFor("detail.hero")
        tap("detail.related.5")
        waitFor("detail.related.2")
        swipeBack()
        waitForDisappearance("detail.related.2")
        swipeBack()

        assertReturns(to: baseline)
    }

    func testReselectingTabPopsToRoot() {
        launch()
        let baseline = settledCounts()

        tap("feed.photo.3")
        waitFor("detail.hero")
        tapTab("Feed")

        waitFor("feed.photo.3")
        assertReturns(to: baseline)
    }

    func testPushedChildFlowFinishFreesCoordinator() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.settings")
        tap("settings.about")
        let inside = settledCounts()
        XCTAssertEqual(inside.coordinators, baseline.coordinators + 1, "Settings coordinator should be alive inside the flow")
        tap("about.done")

        waitFor("profile.editName")
        assertReturns(to: baseline)
    }

    func testPushedChildFlowSwipeBackFreesCoordinator() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.settings")
        tap("settings.notifications")
        swipeBack()
        waitFor("settings.about")
        swipeBack()

        waitFor("profile.editName")
        assertReturns(to: baseline)
    }
}

final class PresentationLifetimeUITests: WaypointUITestCase {
    func testZoomCoverViewerFreesOnClose() {
        launch()
        tap("feed.photo.4")
        waitFor("detail.hero")
        let baseline = settledCounts()

        tap("detail.hero")
        tap("viewer.close")

        waitForDisappearance("viewer.close")
        assertReturns(to: baseline)
    }

    func testSheetSwipedDownFreesPresentation() {
        launch()
        tap("feed.photo.4")
        tap("detail.comments")
        let baseline = settledCountsBeforePresentation()

        let sheetBar = app.navigationBars["Comments"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        let grab = sheetBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        grab.press(forDuration: 0.1, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: 500)))

        waitForDisappearance("close")
        XCTAssertTrue(app.descendants(matching: .any)["detail.hero"].waitForExistence(timeout: 3), "The photo under the sheet should still be shown")
        assertReturns(to: baseline)
    }

    func testEveryDetentDemoFreesOnClose() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        for demo in ["medium", "mediumAndLarge", "fraction", "height", "custom"] {
            tap("lab.detent.\(demo)")
            waitFor("detentDemo")
            screenshot("detent-\(demo)")
            tap("close")
            waitForDisappearance("detentDemo")
        }

        assertReturns(to: baseline)
    }

    func testCoordinatorDrivesDetent() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.controlledDetent")
        let mediumButton = app.buttons["detent.large"]
        XCTAssertTrue(mediumButton.waitForExistence(timeout: 5))
        let mediumY = mediumButton.frame.minY
        mediumButton.tap()
        let movedUp = expectation(for: NSPredicate { _, _ in mediumButton.frame.minY < mediumY - 100 }, evaluatedWith: nil)
        wait(for: [movedUp], timeout: 5)
        tap("detent.small")
        let movedDown = expectation(for: NSPredicate { _, _ in mediumButton.frame.minY > mediumY + 50 }, evaluatedWith: nil)
        wait(for: [movedDown], timeout: 5)
        tap("close")

        assertReturns(to: baseline)
    }

    func testDirtyEditorBlocksSwipeDown() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.editor")
        tap("editor.text")
        app.typeText("draft")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 2), "The dirty editor should stay presented")

        tap("editor.cancel")
        tap("editor.discard")
        waitForDisappearance("editor.cancel")
        assertReturns(to: baseline)
    }

    func testFullScreenCoverFreesOnClose() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.cover")
        waitFor("cover")
        tap("close")

        waitForDisappearance("cover")
        assertReturns(to: baseline)
    }

    func testReplacingSheetWithCoverWaitsForDismissal() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.replace")
        tap("replace.action")

        waitFor("cover", timeout: 6)
        tap("close")
        waitForDisappearance("cover")
        assertReturns(to: baseline)
    }

    func testNestedSheetsDismissAllFreesEveryLevel() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.nested")
        waitFor("nested.level.1")
        tap("nested.presentNext.1")
        waitFor("nested.level.2")
        tap("nested.push.2")
        waitFor("nested.pushedScreen")
        tapBack()
        tap("nested.presentNext.2")
        waitFor("nested.level.3")
        let deep = settledCounts()
        XCTAssertEqual(deep.coordinators, baseline.coordinators + 3)
        tap("nested.dismissAll.3")

        waitForDisappearance("nested.level.1", timeout: 8)
        assertReturns(to: baseline)
    }

    func testNestedSheetsDismissOneLevelAtATime() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.nested")
        tap("nested.presentNext.1")
        waitFor("nested.level.2")
        tap("nested.dismiss.2")
        waitForDisappearance("nested.level.2")
        tap("nested.dismiss.1")

        waitForDisappearance("nested.level.1")
        assertReturns(to: baseline)
    }

    func testZoomSheetAndCoverFromCards() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.card.sheet.2")
        waitFor("close")
        screenshot("zoom-sheet")
        tap("close")
        waitForDisappearance("close")
        tap("lab.card.cover.3")
        waitFor("close")
        tap("close")
        waitForDisappearance("close")
        tap("lab.card.push.4")
        XCTAssertTrue(app.navigationBars["Card 4"].waitForExistence(timeout: 5))
        swipeBack()

        assertReturns(to: baseline)
    }

    /// Opens a flow whose baseline is the screen underneath, already settled.
    private func settledCountsBeforePresentation() -> LiveCounts {
        // The comments sheet is already up. Close it, measure, and reopen it, so the baseline excludes the sheet.
        waitFor("close")
        tap("close")
        waitForDisappearance("close")
        let baseline = settledCounts()
        tap("detail.comments")
        return baseline
    }
}

final class ResultUITests: WaypointUITestCase {
    func testAwaitedPushReturnsValue() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.editName")
        let field = app.textFields["editName.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        app.typeText("Grace")
        tap("editName.save")

        XCTAssertTrue(app.staticTexts["Grace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last result: Edit name: saved \"Grace\""].exists)
        assertReturns(to: baseline)
    }

    func testAwaitedPushReturnsNilOnSwipeBack() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.editName")
        waitFor("editName.field")
        swipeBack()

        XCTAssertTrue(app.staticTexts["Last result: Edit name: cancelled"].waitForExistence(timeout: 5))
        assertReturns(to: baseline)
    }

    func testAwaitedSheetReturnsValue() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.pickColor")
        tap("color.teal")

        XCTAssertTrue(app.staticTexts["Last result: Pick color: Teal"].waitForExistence(timeout: 5))
        assertReturns(to: baseline)
    }

    func testAwaitedSheetReturnsNilOnSwipeDown() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.pickColor")
        waitFor("color.teal")
        app.swipeDown(velocity: .fast)

        XCTAssertTrue(app.staticTexts["Last result: Pick color: dismissed"].waitForExistence(timeout: 5))
        assertReturns(to: baseline)
    }

    func testSwiftUIEnvironmentDismissIsObserved() {
        launch()
        tapTab("Profile")
        let baseline = settledCounts()

        tap("profile.pickColor")
        tap("close")

        XCTAssertTrue(app.staticTexts["Last result: Pick color: dismissed"].waitForExistence(timeout: 5))
        assertReturns(to: baseline)
    }

    func testPushedChildFlowReturnsValueAndPopsAllSteps() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.wizard")
        tap("wizard.option.Alpha")
        tap("wizard.option.Bravo")
        tap("wizard.option.Charlie")

        let result = app.descendants(matching: .any)["lab.wizardResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alpha → Bravo → Charlie"].exists || result.label.contains("Alpha → Bravo → Charlie"), "Got \(result.label)")
        assertReturns(to: baseline)
    }

    func testPushedChildFlowReturnsNilWhenPopped() {
        launch()
        tapTab("Explore")
        let baseline = settledCounts()

        tap("lab.wizard")
        tap("wizard.option.Alpha")
        waitFor("wizard.option.Bravo")
        tapTab("Explore")

        let result = app.descendants(matching: .any)["lab.wizardResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cancelled (popped before finishing)"].exists || result.label.contains("Cancelled"), "Got \(result.label)")
        assertReturns(to: baseline)
    }
}

final class RootAndDeepLinkUITests: WaypointUITestCase {
    func testSignOutAndBackInFreesEverything() {
        launch()
        let signedIn = settledCounts()

        // Leave state everywhere so the teardown has work to do.
        tap("feed.photo.1")
        waitFor("detail.hero")
        tapTab("Explore")
        tap("lab.wizard")
        waitFor("wizard.option.Alpha")
        tapTab("Profile")
        tap("profile.settings")
        tap("settings.signOut")
        let confirm = app.alerts.buttons["Sign out"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        waitFor("welcome.signIn")
        // Only the auth flow is left: one coordinator, one navigator, one screen, no view models.
        let signedOut = settledCounts()
        XCTAssertEqual(signedOut.coordinators, 1, "\(signedOut). \(lifetime.label)")
        XCTAssertEqual(signedOut.navigators, 1, "\(signedOut). \(lifetime.label)")
        XCTAssertEqual(signedOut.entries, 1, "\(signedOut). \(lifetime.label)")

        tap("welcome.signIn")
        let password = app.secureTextFields["signIn.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        app.typeText("1234")
        tap("signIn.submit")

        waitFor("feed.photo.1", timeout: 8)
        tapTab("Explore")
        tapTab("Profile")
        tapTab("Feed")
        assertReturns(to: signedIn)
    }

    func testForgotPasswordSheetInAuthFlow() {
        launch(signedIn: false)
        tap("welcome.signIn")
        let baseline = settledCounts()

        tap("signIn.forgot")
        tap("forgot.action")
        tap("forgot.action")

        waitForDisappearance("forgot.action")
        assertReturns(to: baseline)
    }

    func testOnboardingReturnsUserAndSwitchesRoot() {
        launch(signedIn: false)

        tap("welcome.createAccount")
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        app.typeText("Linus")
        tap("onboarding.next")
        tap("onboarding.next")
        tap("onboarding.next")
        tap("onboarding.finish")

        waitFor("feed.photo.1", timeout: 8)
        let counts = settledCounts()
        XCTAssertEqual(counts.coordinators, 3, "Only the three tab coordinators should be alive: \(counts)")
        tapTab("Profile")
        XCTAssertTrue(app.staticTexts["Linus"].waitForExistence(timeout: 5))
    }

    func testCancellingOnboardingFreesTheFlow() {
        launch(signedIn: false)
        let baseline = settledCounts()

        tap("welcome.createAccount")
        tap("onboarding.cancel")

        waitFor("welcome.signIn")
        assertReturns(to: baseline)
    }

    func testDeepLinkToPhotoFromAnotherTab() {
        launch()
        tapTab("Explore")
        tap("lab.cover")
        waitFor("cover")

        open("waypoint://feed/photo/6")

        XCTAssertTrue(app.navigationBars["Fish"].waitForExistence(timeout: 8))
    }

    func testDeepLinkIntoNestedSettings() {
        launch()

        open("waypoint://profile/settings/about")

        waitFor("about.done", timeout: 8)
        tap("about.done")
        waitFor("profile.editName")
    }

    func testDeepLinkToStackedSheets() {
        launch()

        open("waypoint://explore/nested/3")

        waitFor("nested.level.3", timeout: 10)
        tap("nested.dismissAll.3")
        waitForDisappearance("nested.level.1", timeout: 8)
    }

    func testDeepLinkWhileSignedOutOpensAfterSignIn() {
        launch(signedIn: false)

        open("waypoint://profile/settings")
        tap("welcome.signIn")
        let password = app.secureTextFields["signIn.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        app.typeText("1234")
        tap("signIn.submit")

        waitFor("settings.about", timeout: 8)
    }

    private func open(_ link: String) {
        XCUIDevice.shared.system.open(URL(string: link)!)
        // The system may ask to confirm opening the app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButton = springboard.buttons["Open"]
        if openButton.waitForExistence(timeout: 2) { openButton.tap() }
    }
}
