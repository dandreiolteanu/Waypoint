import Foundation

/// Every link the app handles, parsed once at the edge into values, then handed down the coordinator tree:
///
/// 1. `AppCoordinator` gates on sign-in, parking the link until the user is signed in.
/// 2. `MainCoordinator` checks for unsaved work, picks the tab, and resets it.
/// 3. The tab's coordinator navigates inside its own flow, with its own link type.
///
/// Each feature owns its piece of the link (`FeedLink`, `ProfileLink`, …), so adding a screen never touches the others.
///
/// | URL | Opens |
/// | --- | --- |
/// | `waypoint://feed/photo/3` | Photo 3 in Feed |
/// | `waypoint://albums/sky` | The Sky album |
/// | `waypoint://albums/sky/photo/7` | Photo 7 inside the Sky album |
/// | `waypoint://explore/nested/3` | Three stacked sheets |
/// | `waypoint://explore/editor` | The unsaved-changes editor |
/// | `waypoint://profile/settings` | Settings (`/about`, `/notifications` go deeper) |
/// | `waypoint://profile/color` | The color picker; the picked color is saved |
enum DeepLink: Equatable {
    case feed(FeedLink)
    case albums(AlbumsLink)
    case explore(ExploreLink)
    case profile(ProfileLink)

    init?(url: URL) {
        guard url.scheme == "waypoint", let host = url.host() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        let link: DeepLink? = switch host {
        case "feed": FeedLink(path: path).map(DeepLink.feed)
        case "albums": AlbumsLink(path: path).map(DeepLink.albums)
        case "explore": ExploreLink(path: path).map(DeepLink.explore)
        case "profile": ProfileLink(path: path).map(DeepLink.profile)
        default: nil
        }
        guard let link else { return nil }
        self = link
    }
}

enum FeedLink: Equatable {
    case photo(id: Int)

    init?(path: [String]) {
        guard path.first == "photo", let id = path.dropFirst().first.flatMap(Int.init) else { return nil }
        self = .photo(id: id)
    }
}

enum AlbumsLink: Equatable {
    case album(Album, photo: Int?)

    init?(path: [String]) {
        guard let album = path.first.flatMap(Album.init(rawValue:)) else { return nil }
        let photo = path.count >= 3 && path[1] == "photo" ? Int(path[2]) : nil
        self = .album(album, photo: photo)
    }
}

enum ExploreLink: Equatable {
    case nestedSheets(depth: Int)
    case editor

    init?(path: [String]) {
        switch path.first {
        case "nested": self = .nestedSheets(depth: path.dropFirst().first.flatMap(Int.init) ?? 2)
        case "editor": self = .editor
        default: return nil
        }
    }
}

enum ProfileLink: Equatable {
    case settings(SettingsCoordinator.Route?)
    case pickColor

    init?(path: [String]) {
        switch path.first {
        case "settings": self = .settings(path.dropFirst().first.flatMap(SettingsCoordinator.Route.init(pathComponent:)))
        case "color": self = .pickColor
        default: return nil
        }
    }
}

/// Push notifications carry a link in their payload and go through the same path as any URL.
/// From `userNotificationCenter(_:didReceive:)`, open the URL: the system routes it to the right window's `onOpenURL`.
enum NotificationRouting {
    static func url(from userInfo: [AnyHashable: Any]) -> URL? {
        (userInfo["link"] as? String).flatMap(URL.init(string:))
    }
}
