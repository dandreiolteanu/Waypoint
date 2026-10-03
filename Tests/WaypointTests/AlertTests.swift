import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Alerts")
struct AlertTests {
    @Test("Tapping a button returns its value and clears the alert")
    func tappedValue() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.alert("Pick", actions: [AlertAction("One", value: 1), AlertAction("Two", value: 2)]) }
        await settle()
        let request = try #require(navigator.alertRequest)

        // WHEN
        navigator.finishAlert(request, choosing: 1)

        // THEN
        #expect(await task.value == 2)
        #expect(navigator.alertRequest == nil)
    }

    @Test("A dismissal without a choice, then the button action, still returns the button's value")
    func buttonWinsOverDismissal() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.confirm("Sure?", confirmTitle: "Yes") }
        await settle()
        let request = try #require(navigator.alertRequest)

        // WHEN: SwiftUI writes isPresented = false, then runs the button's action
        navigator.finishAlert(request, choosing: nil)
        navigator.finishAlert(request, choosing: 0)

        // THEN
        #expect(await task.value == true)
    }

    @Test("A dismissal without a choice returns nil, and confirm returns false")
    func dismissedWithoutChoice() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.confirm("Sure?", confirmTitle: "Yes", style: .confirmationDialog) }
        await settle()
        let request = try #require(navigator.alertRequest)
        #expect(request.style == .confirmationDialog)

        // WHEN
        navigator.finishAlert(request, choosing: nil)

        // THEN
        #expect(await task.value == false)
    }

    @Test("Alerts appear on the topmost presented navigator")
    func topmost() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.present(child: child)

        // WHEN
        let task = Task { await home.confirm("Sure?", confirmTitle: "Yes") }
        await settle()

        // THEN
        #expect(navigator.alertRequest == nil)
        let presented = try #require(child.navigator)
        let request = try #require(presented.alertRequest)
        presented.finishAlert(request, choosing: 0)
        #expect(await task.value == true)
    }

    @Test("A second alert replaces the first, which returns nil")
    func replaced() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let first = Task { await home.alert("First", actions: [AlertAction("OK", value: 1)]) }
        await settle()

        // WHEN
        let second = Task { await home.alert("Second", actions: [AlertAction("OK", value: 2)]) }
        await settle()

        // THEN
        #expect(await first.value == nil)
        let request = try #require(navigator.alertRequest)
        #expect(request.title == "Second")
        navigator.finishAlert(request, choosing: 0)
        #expect(await second.value == 2)
    }

    @Test("Tearing the navigator down resolves its alert with nil")
    func teardown() async {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.alert("Pick", actions: [AlertAction("One", value: 1)]) }
        await settle()

        // WHEN
        navigator.tearDown()

        // THEN
        #expect(await task.value == nil)
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }
}
