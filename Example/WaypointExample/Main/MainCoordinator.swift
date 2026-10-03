import SwiftUI
import Waypoint

/// Owns the three tabs. Each tab is a navigator with its own coordinator at the root.
@MainActor
final class MainCoordinator {
    enum Tab: Hashable {
        case feed, explore, profile
    }

    let tabs: TabNavigator<Tab>
    // Held so deep links can reach them. The tab navigators own them as well. Neither holds this coordinator back, so there's no cycle.
    private let feed: FeedCoordinator
    private let explore: ExploreCoordinator
    private let profile: ProfileCoordinator

    init(session: SessionStore, onSignOut: @escaping () -> Void) {
        feed = FeedCoordinator()
        explore = ExploreCoordinator()
        profile = ProfileCoordinator(session: session, onSignOut: onSignOut)
        tabs = TabNavigator(selectedTab: .feed, tabs: [
            .feed: Navigator(root: feed),
            .explore: Navigator(root: explore),
            .profile: Navigator(root: profile)
        ])
    }

    func open(_ link: DeepLink) {
        switch link {
        case let .photo(id):
            tabs.select(.feed, popToRoot: true)
            feed.showPhoto(id: id, transition: .automatic)
        case let .nestedSheets(depth):
            tabs.select(.explore, popToRoot: true)
            explore.showNestedSheets(depth: depth)
        case let .settings(section):
            tabs.select(.profile, popToRoot: true)
            profile.showSettings(section: section)
        }
    }

    func tearDown() {
        tabs.tearDown()
    }
}

/// Holds the tabs weakly. SwiftUI can keep a removed `TabView` alive after a root switch, and a strong reference here
/// would keep every tab's coordinators and view models with it. The app coordinator owns the tabs, so the view doesn't need to.
struct MainView: View {
    weak var tabs: TabNavigator<MainCoordinator.Tab>?

    var body: some View {
        if let tabs {
            TabView(selection: tabs.selection) {
                Tab("Feed", systemImage: "photo.on.rectangle.angled", value: .feed) {
                    NavigationHost(tabs[.feed])
                }
                Tab("Explore", systemImage: "rectangle.stack", value: .explore) {
                    NavigationHost(tabs[.explore])
                }
                Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                    NavigationHost(tabs[.profile])
                }
            }
        }
    }
}
