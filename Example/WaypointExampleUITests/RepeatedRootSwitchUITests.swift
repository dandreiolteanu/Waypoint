import XCTest

/// Signing out and back in, again and again, must not pile up old tabs. Some OS versions keep a removed TabView's
/// background tabs alive indefinitely unless the TabView is dismantled while still mounted, which TabHost does.
final class RepeatedRootSwitchUITests: WaypointUITestCase {
    func testRepeatedSignOutDoesNotAccumulate() {
        launch()
        let signedIn = settledCounts()
        for round in 1...3 {
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
            tap("welcome.signIn")
            let password = app.secureTextFields["signIn.password"]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            password.tap()
            app.typeText("1234")
            tap("signIn.submit")
            waitFor("feed.photo.1", timeout: 8)
            tapTab("Explore"); tapTab("Profile"); tapTab("Feed")
            XCTContext.runActivity(named: "Round \(round)") { _ in
                assertReturns(to: signedIn)
            }
        }
    }
}
