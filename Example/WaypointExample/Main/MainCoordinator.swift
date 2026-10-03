import SwiftUI
import Waypoint

/// Owns the three tabs. Each tab is a navigator with its own coordinator at the root.
@MainActor
final class MainCoordinator {
    enum Tab: Hashable, CaseIterable {
        case feed, explore, profile
    }

    let tabs: TabNavigator<Tab>

    init(session: SessionStore, onSignOut: @escaping () -> Void) {
        tabs = TabNavigator(selected: .feed) { tab in
            switch tab {
            case .feed: Navigator(root: FeedCoordinator())
            case .explore: Navigator(root: ExploreCoordinator())
            case .profile: Navigator(root: ProfileCoordinator(session: session, onSignOut: onSignOut))
            }
        }
    }

    func open(_ link: DeepLink) {
        switch link {
        case let .photo(id):
            tabs.select(.feed, reset: true)
            tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.showPhoto(id: id, transition: .automatic)
        case let .nestedSheets(depth):
            tabs.select(.explore, reset: true)
            tabs.coordinator(for: .explore, as: ExploreCoordinator.self)?.showNestedSheets(depth: depth)
        case let .settings(section):
            tabs.select(.profile, reset: true)
            tabs.coordinator(for: .profile, as: ProfileCoordinator.self)?.showSettings(section: section)
        }
    }

    func tearDown() {
        tabs.tearDown()
    }
}

struct MainView: View {
    let tabs: TabNavigator<MainCoordinator.Tab>

    var body: some View {
        // TabHost holds the tabs weakly: SwiftUI can keep a removed TabView around after sign-out, and it must not keep the tabs with it.
        TabHost(tabs) { tabs in
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
