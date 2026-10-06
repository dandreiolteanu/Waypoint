import XCTest

/// The live object counts the lifetime overlay publishes as its accessibility value: "c=3 n=3 e=3 vm=3".
struct LiveCounts: Equatable, CustomStringConvertible {
    let coordinators: Int
    let navigators: Int
    let entries: Int
    let viewModels: Int

    init?(_ value: String) {
        let pairs = Dictionary(uniqueKeysWithValues: value.split(separator: " ").compactMap { part -> (String, Int)? in
            let kv = part.split(separator: "=")
            guard kv.count == 2, let number = Int(kv[1]) else { return nil }
            return (String(kv[0]), number)
        })
        guard let c = pairs["c"], let n = pairs["n"], let e = pairs["e"], let vm = pairs["vm"] else { return nil }
        coordinators = c
        navigators = n
        entries = e
        viewModels = vm
    }

    var description: String { "c=\(coordinators) n=\(navigators) e=\(entries) vm=\(viewModels)" }
}

class WaypointUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Every failure carries a screenshot and the live object names, for triage from the result bundle.
    override func record(_ issue: XCTIssue) {
        var issue = issue
        if let app {
            issue.add(XCTAttachment(screenshot: app.screenshot()))
            if lifetime.exists {
                issue.add(XCTAttachment(string: lifetime.label))
            }
        }
        super.record(issue)
    }

    func launch(signedIn: Bool = true) {
        app.launchArguments = signedIn ? ["-signedIn"] : []
        app.launch()
        XCTAssertTrue(app.otherElements["lifetime"].waitForExistence(timeout: 10) || app.staticTexts["lifetime"].exists)
    }

    var lifetime: XCUIElement {
        app.descendants(matching: .any)["lifetime"]
    }

    var counts: LiveCounts? {
        guard lifetime.exists, let value = lifetime.value as? String else { return nil }
        return LiveCounts(value)
    }

    /// Waits for the counts to settle (unchanged across a few polls), then returns them.
    func settledCounts(file: StaticString = #filePath, line: UInt = #line) -> LiveCounts {
        var last: LiveCounts?
        var stableReads = 0
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let current = counts
            if current != nil, current == last {
                stableReads += 1
                if stableReads >= 3 { return current! }
            } else {
                stableReads = 0
            }
            last = current
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("Counts never settled (last: \(String(describing: last)))", file: file, line: line)
        return last!
    }

    /// Asserts that leaving a flow brings every live count back to `baseline`, which proves its objects were freed.
    func assertReturns(to baseline: LiveCounts, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var current = counts
        while Date() < deadline {
            current = counts
            if current == baseline { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("Leak: expected \(baseline), still \(String(describing: current)). \(lifetime.label)", file: file, line: line)
    }

    /// Taps a tab: in the bottom tab bar on iPhone, or the floating tab bar (or sidebar) on iPad.
    func tapTab(_ name: String) {
        let barButton = app.tabBars.buttons[name]
        if barButton.exists {
            barButton.tap()
        } else {
            let button = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "No tab named \(name)")
            button.tap()
        }
    }

    func tap(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if !element.waitForExistence(timeout: timeout) || !element.isHittable {
            // Lazy lists only build visible rows. Scroll down until the row shows up.
            for _ in 0..<6 where !(element.exists && element.isHittable) {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(element.exists, "Missing \(identifier)", file: file, line: line)
        // A row under the translucent tab bar reports as hittable, but the tap lands on the bar. Scroll it clear first.
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            for _ in 0..<4 where element.frame.maxY > tabBar.frame.minY - 8 && element.frame.minY > 0 {
                app.swipeUp(velocity: .slow)
            }
        }
        element.tap()
    }

    func waitFor(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: timeout), "Missing \(identifier)", file: file, line: line)
    }

    func waitForDisappearance(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, "\(identifier) is still on screen", file: file, line: line)
    }

    func tapBack() {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 3) {
            back.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// An interactive swipe from the left edge, like a user's swipe-back.
    func swipeBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// An interactive swipe down from the top of the topmost sheet's navigation bar.
    func swipeSheetDown() {
        let bar = app.navigationBars.allElementsBoundByIndex.last ?? app.navigationBars.firstMatch
        let grab = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        grab.press(forDuration: 0.05, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: 700)))
    }

    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
