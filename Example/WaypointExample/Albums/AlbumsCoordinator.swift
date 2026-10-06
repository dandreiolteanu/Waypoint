import SwiftUI
import Waypoint

/// The Albums tab: a `NavigationSplitView`. The sidebar lists albums; the detail column is a full flow (a
/// `FeedCoordinator` for the album) built for each selection. On iPad they sit side by side; on iPhone the split
/// collapses into one stack, where picking an album pushes it.
///
/// The tab's navigator doesn't embed a NavigationStack (`embedsInNavigationStack: false`): a split view must not sit
/// inside one. The split navigator is owned here, and torn down when this flow ends.
@MainActor
final class AlbumsCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case library
    }

    // On iPad, start with an album selected and both columns showing, so neither column is ever empty.
    let split = SplitNavigator<Album>(
        selected: UIDevice.current.userInterfaceIdiom == .pad ? .landscapes : nil,
        columnVisibility: .all
    ) { album in
        Navigator(root: FeedCoordinator(title: album.title, photos: album.photos))
    }

    var initialRoute: Route { .library }

    func destination(for route: Route) -> some View {
        SplitHost(split) { split in
            List(Album.allCases, selection: split.selection) { album in
                Label(album.title, systemImage: album.icon)
                    .accessibilityIdentifier("album.\(album.rawValue)")
            }
            .navigationTitle("Albums")
        } placeholder: {
            ContentUnavailableView("Pick an album", systemImage: "photo.on.rectangle.angled")
        }
    }

    override func didFinish() {
        split.tearDown()
    }

    func open(_ link: AlbumsLink) {
        switch link {
        case let .album(album, photo):
            split.select(album, reset: true)
            if let photo {
                split.detailCoordinator(as: FeedCoordinator.self)?.showPhoto(id: photo, transition: .automatic)
            }
        }
    }
}
