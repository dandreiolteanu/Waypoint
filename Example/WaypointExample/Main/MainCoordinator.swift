import SwiftUI
import Waypoint

/// Owns the tabs. Each tab is a navigator with its own coordinator at the root.
@MainActor
final class MainCoordinator {
    enum Tab: Hashable, CaseIterable {
        case feed, albums, explore, profile
    }

    let tabs: TabNavigator<Tab>

    init(session: SessionStore, onSignOut: @escaping () -> Void) {
        tabs = TabNavigator(selected: .feed) { tab in
            switch tab {
            case .feed: Navigator(root: FeedCoordinator())
            // A split view is its own container, so this tab's navigator has no NavigationStack around it.
            case .albums: Navigator(root: AlbumsCoordinator(), embedsInNavigationStack: false)
            case .explore: Navigator(root: ExploreCoordinator())
            case .profile: Navigator(root: ProfileCoordinator(session: session, onSignOut: onSignOut))
            }
        }
    }

    /// The middle of the deep link path: protect unsaved work, pick the tab, give it a clean slate,
    /// and let the tab's own coordinator handle the rest of the link.
    func open(_ link: DeepLink) async {
        if let explore = tabs.coordinator(for: .explore, as: ExploreCoordinator.self) {
            guard await explore.confirmLeavingUnsavedWork() else { return }
        }
        switch link {
        case let .feed(link):
            tabs.select(.feed, reset: true)
            tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.open(link)
        case let .albums(link):
            tabs.select(.albums, reset: true)
            tabs.coordinator(for: .albums, as: AlbumsCoordinator.self)?.open(link)
        case let .explore(link):
            tabs.select(.explore, reset: true)
            tabs.coordinator(for: .explore, as: ExploreCoordinator.self)?.open(link)
        case let .profile(link):
            tabs.select(.profile, reset: true)
            await tabs.coordinator(for: .profile, as: ProfileCoordinator.self)?.open(link)
        }
    }

    func tearDown() {
        tabs.tearDown()
    }
}

struct MainView: View {
    let tabs: TabNavigator<MainCoordinator.Tab>

    var body: some View {
        TabHost(tabs) { tabs in
            TabView(selection: tabs.selection) {
                Tab("Feed", systemImage: "photo.on.rectangle.angled", value: .feed) {
                    NavigationHost(tabs[.feed])
                }
                Tab("Albums", systemImage: "rectangle.stack.badge.person.crop", value: .albums) {
                    NavigationHost(tabs[.albums])
                }
                Tab("Explore", systemImage: "rectangle.stack", value: .explore) {
                    NavigationHost(tabs[.explore])
                }
                Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                    NavigationHost(tabs[.profile])
                }
            }
            // A tab bar on iPhone; on iPad, a tab bar that people can turn into a sidebar.
            .tabViewStyle(.sidebarAdaptable)
        }
    }
}
