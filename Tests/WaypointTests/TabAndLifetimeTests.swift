import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Tabs")
struct TabTests {
    enum AppTab: Hashable, CaseIterable { case feed, profile }

    private func makeTabs() -> (TabNavigator<AppTab>, feed: TestCoordinator, profile: TestCoordinator) {
        let feed = TestCoordinator()
        let profile = TestCoordinator()
        let tabs = TabNavigator(selected: AppTab.feed) { tab in
            switch tab {
            case .feed: Navigator(root: feed)
            case .profile: Navigator(root: profile)
            }
        }
        return (tabs, feed, profile)
    }

    @Test("Selecting another tab keeps each tab's stack")
    func switchTabs() {
        // GIVEN
        let (tabs, feed, _) = makeTabs()
        feed.push(.detail(1))

        // WHEN
        tabs.selection.wrappedValue = .profile

        // THEN
        #expect(tabs.selectedTab == .profile)
        #expect(feed.routes == [.home, .detail(1)])
    }

    @Test("Reselecting the current tab pops it to root")
    func reselect() {
        // GIVEN
        let (tabs, feed, _) = makeTabs()
        feed.push([.detail(1), .detail(2)])

        // WHEN
        tabs.selection.wrappedValue = .feed

        // THEN
        #expect(feed.routes == [.home])
    }

    @Test("Reselecting doesn't pop when the option is off")
    func reselectDisabled() {
        // GIVEN
        let (tabs, feed, _) = makeTabs()
        tabs.popsToRootOnReselect = false
        feed.push(.detail(1))

        // WHEN
        tabs.selection.wrappedValue = .feed

        // THEN
        #expect(feed.routes == [.home, .detail(1)])
    }

    @Test("select(_:popToRoot:) resets the target tab for deep links")
    func selectPoppingToRoot() {
        // GIVEN
        let (tabs, _, profile) = makeTabs()
        profile.push(.detail(1))
        profile.present(.detail(2))

        // WHEN
        tabs.select(.profile, reset: true)

        // THEN
        #expect(tabs.selectedTab == .profile)
        #expect(profile.routes == [.home])
        #expect(tabs[.profile].presentation == nil)
    }

    @Test("A torn-down TabNavigator still held by a view keeps nothing alive")
    func teardownReleasesNavigators() {
        // GIVEN
        weak var weakFeedNavigator: Navigator?
        weak var weakFeed: TestCoordinator?
        let tabs: TabNavigator<AppTab>
        do {
            let (made, feed, _) = makeTabs()
            tabs = made
            weakFeedNavigator = made[.feed]
            weakFeed = feed
            feed.push(.detail(1))
        }

        // WHEN: torn down, but something (a stale view) still holds `tabs`
        tabs.tearDown()

        // THEN
        #expect(weakFeedNavigator == nil)
        #expect(weakFeed == nil)
        #expect(tabs.coordinator(for: .feed, as: TestCoordinator.self) == nil)
        #expect(tabs[.feed] === tabs[.profile], "A stale view gets the shared empty placeholder")
    }

    @Test("Tearing the tabs down finishes every tab's coordinators")
    func teardown() {
        // GIVEN
        let (tabs, feed, profile) = makeTabs()

        // WHEN
        tabs.tearDown()

        // THEN
        #expect(feed.isFinished && profile.isFinished)
    }
}

@MainActor
@Suite("Memory")
struct LifetimeTests {
    @Test("Dropping a whole tree (a root switch) frees every navigator, entry, coordinator and view model")
    func rootSwitchFreesEverything() {
        weak var weakRootNavigator: Navigator?
        weak var weakHome: TestCoordinator?
        weak var weakPushedChild: ChildFlowCoordinator?
        weak var weakPresentedChild: ChildFlowCoordinator?
        weak var weakNestedChild: ChildFlowCoordinator?
        var viewModels = WeakList<TestViewModel>()
        var childViewModels = WeakList<ChildViewModel>()
        var tabs: TabNavigator<Int>?

        do {
            // GIVEN: a deep tree of pushes and presentations in one tab
            let home = TestCoordinator()
            let navigator = Navigator(root: home)
            tabs = TabNavigator(selected: 0, tabs: [0]) { _ in navigator }
            home.push([.detail(1), .detail(2)])
            let pushed = ChildFlowCoordinator()
            home.pushFlow(pushed)
            pushed.push(.step(2))
            let presented = ChildFlowCoordinator()
            pushed.presentFlow(presented)
            presented.push(.step(2))
            let nested = ChildFlowCoordinator()
            presented.presentFlow(nested, as: .fullScreenCover)
            home.madeViewModels.all.compactMap { $0 }.forEach { viewModels.append($0) }
            for child in [pushed, presented, nested] {
                child.madeViewModels.all.compactMap { $0 }.forEach { childViewModels.append($0) }
            }
            weakRootNavigator = navigator
            weakHome = home
            weakPushedChild = pushed
            weakPresentedChild = presented
            weakNestedChild = nested
        }
        #expect(viewModels.liveCount == 3)
        #expect(childViewModels.liveCount == 5)

        // WHEN: the app switches root and drops the tabs
        tabs?.tearDown()
        tabs = nil

        // THEN
        #expect(weakRootNavigator == nil)
        #expect(weakHome == nil)
        #expect(weakPushedChild == nil)
        #expect(weakPresentedChild == nil)
        #expect(weakNestedChild == nil)
        #expect(viewModels.liveCount == 0)
        #expect(childViewModels.liveCount == 0)
    }

    @Test("A view model holding its coordinator strongly doesn't create a cycle")
    func noCycleThroughViewModel() {
        weak var weakHome: TestCoordinator?
        weak var weakViewModel: TestViewModel?
        do {
            let home = TestCoordinator()
            var navigator: Navigator? = Navigator(root: home)
            weakHome = home
            weakViewModel = home.madeViewModels.all.first ?? nil
            #expect(weakViewModel?.coordinator === home)
            navigator = nil
            _ = navigator
        }
        #expect(weakHome == nil)
        #expect(weakViewModel == nil)
    }

    @Test("Pushing and popping many screens leaves nothing behind")
    func churn() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        for round in 0..<50 {
            home.push((0..<20).map { .detail(round * 100 + $0) })
            let child = ChildFlowCoordinator()
            home.presentFlow(child)
            child.push(.step(2))
            navigator.dismissPresentation()
            navigator.pop(count: 10)
            navigator.popToRoot()
        }

        // THEN
        #expect(home.madeViewModels.count == 1 + 50 * 20)
        #expect(home.madeViewModels.liveCount == 1)
    }

    @Test("The lifetime tracker counts live objects by type")
    func tracker() {
        // GIVEN
        final class TrackedThing {}
        var thing: TrackedThing? = TrackedThing()
        LifetimeTracker.track(thing!, kind: .viewModel)
        #expect(LifetimeTracker.liveTypeNames(of: .viewModel).contains("TrackedThing"))

        // WHEN
        thing = nil

        // THEN
        #expect(!LifetimeTracker.liveTypeNames(of: .viewModel).contains("TrackedThing"))
    }
}
