import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Awaiting results")
struct ResultTests {
    @Test("A pushed screen's callback returns its value and pops the screen")
    func pushedValue() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.push { .edit("Ada", onSave: $0) } }
        await settle()
        let callback = try #require(editCallback(in: navigator.top))

        // WHEN
        callback("Grace")

        // THEN
        #expect(await task.value == "Grace")
        #expect(navigator.path.isEmpty)
    }

    @Test("Popping a screen that was waiting for a result returns nil")
    func pushedPopped() async {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.push { .edit("Ada", onSave: $0) } }
        await settle()

        // WHEN
        navigator.pop()

        // THEN
        #expect(await task.value == nil)
    }

    @Test("A presented screen's callback returns its value and dismisses it")
    func presentedValue() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.present(as: .sheet(detents: [.medium])) { .pick($0) } }
        await settle()
        let root = try #require(navigator.presentation?.navigator.root)
        let callback = try #require(pickCallback(in: root))

        // WHEN
        callback(7)

        // THEN
        #expect(await task.value == 7)
        #expect(navigator.presentation == nil)
    }

    @Test("Swiping a presented screen away returns nil")
    func presentedSwipedAway() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.present { .pick($0) } }
        await settle()

        // WHEN
        navigator.presentationDismissedBySystem(try #require(navigator.presentation))

        // THEN
        #expect(await task.value == nil)
    }

    @Test("A presented child flow returns its value, is dismissed, and is freed")
    func presentedChildValue() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        weak var weakChild: ChildFlowCoordinator?
        let task = Task {
            await home.present(as: .fullScreenCover) { callback in
                let child = ChildFlowCoordinator(onComplete: callback)
                weakChild = child
                return child
            }
        }
        await settle()
        let child = try #require(weakChild)
        child.push(.step(2))

        // WHEN
        child.complete(with: "done")

        // THEN
        #expect(await task.value == "done")
        #expect(navigator.presentation == nil)
        #expect(child.isFinished)
        #expect(child.madeViewModels.liveCount == 0)
    }

    @Test("A pushed child flow returns its value and pops all of its screens")
    func pushedChildValue() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push(.detail(1))
        weak var weakChild: ChildFlowCoordinator?
        let task = Task {
            await home.push(child: { callback in
                let child = ChildFlowCoordinator(onComplete: callback)
                weakChild = child
                return child
            })
        }
        await settle()
        let child = try #require(weakChild)
        child.push([.step(2), .step(3)])

        // WHEN
        child.complete(with: "ok")

        // THEN
        #expect(await task.value == "ok")
        #expect(home.routes == [.home, .detail(1)])
    }

    @Test("Calling a callback twice resumes the await once")
    func doubleCallback() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.push { .pick($0) } }
        await settle()
        let callback = try #require(pickCallback(in: navigator.top))

        // WHEN
        callback(1)
        callback(2)

        // THEN
        #expect(await task.value == 1)
    }

    @Test("Tearing the navigator down resolves pending results with nil")
    func teardown() async {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let pushed = Task { await home.push { .pick($0) } }
        await settle()
        let presented = Task { await home.present { .pick($0) } }
        await settle()

        // WHEN
        navigator.tearDown()

        // THEN
        #expect(await pushed.value == nil)
        #expect(await presented.value == nil)
    }

    @Test("Dropping a navigator without tearing it down still resolves pending results with nil")
    func droppedTree() async {
        // GIVEN
        var navigator: Navigator? = Navigator(root: TestCoordinator())
        let task = Task { [weak navigator] in
            let home = navigator?.root.owner as? TestCoordinator
            return await home?.push { .pick($0) }
        }
        await settle()

        // WHEN
        navigator = nil

        // THEN
        #expect(await task.value == nil)
    }

    @Test("Awaiting from a coordinator that was never started returns nil right away")
    func unstartedAwait() async {
        // GIVEN
        let coordinator = TestCoordinator()

        // WHEN
        // Not started yet: requireNavigator asserts in debug, so only check the finished case.
        let navigator = Navigator(root: coordinator)
        navigator.tearDown()
        let value = await coordinator.push { .pick($0) }

        // THEN
        #expect(value == nil)
    }

    @Test("A callback fired after its screen was popped is ignored")
    func lateCallback() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.push { .pick($0) } }
        await settle()
        let callback = try #require(pickCallback(in: navigator.top))
        home.push(.detail(9))
        navigator.pop(count: 2)
        #expect(await task.value == nil)

        // WHEN
        callback(5)

        // THEN: nothing else was popped
        #expect(navigator.path.isEmpty)
        #expect(home.routes == [.home])
    }

    @Test("Callbacks with different identities are different routes")
    func callbackIdentity() {
        let first = Callback<Int> { _ in }
        let second = Callback<Int> { _ in }

        #expect(first == first)
        #expect(first != second)
        #expect(TestCoordinator.Route.pick(first) != .pick(second))
    }

    // MARK: - Helpers

    /// Lets the `Task`s above run up to their first suspension point.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    private func editCallback(in entry: StackEntry) -> Callback<String>? {
        guard case let .edit(_, onSave) = entry.route(as: TestCoordinator.Route.self) else { return nil }
        return onSave
    }

    private func pickCallback(in entry: StackEntry) -> Callback<Int>? {
        guard case let .pick(onPick) = entry.route(as: TestCoordinator.Route.self) else { return nil }
        return onPick
    }
}
