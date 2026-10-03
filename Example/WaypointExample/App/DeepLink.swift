import Foundation

/// The links the example understands:
///
/// - `waypoint://feed/photo/3` opens photo 3 in the Feed tab.
/// - `waypoint://explore/nested/3` opens three stacked sheets in Explore.
/// - `waypoint://profile/settings` opens Settings, and `.../settings/about` opens About inside it.
enum DeepLink: Equatable {
    case photo(id: Int)
    case nestedSheets(depth: Int)
    case settings(SettingsCoordinator.Route?)

    init?(url: URL) {
        guard url.scheme == "waypoint", let host = url.host() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (host, parts.first) {
        case ("feed", "photo"):
            guard let id = parts.dropFirst().first.flatMap(Int.init) else { return nil }
            self = .photo(id: id)
        case ("explore", "nested"):
            self = .nestedSheets(depth: parts.dropFirst().first.flatMap(Int.init) ?? 2)
        case ("profile", "settings"):
            self = .settings(parts.dropFirst().first.flatMap(SettingsCoordinator.Route.init(pathComponent:)))
        default:
            return nil
        }
    }
}
