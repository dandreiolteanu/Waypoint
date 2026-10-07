import SwiftUI
import Waypoint

/// Zoom transitions: grid → detail is a zoom push, detail → viewer is a zoom full-screen cover, and comments are a sheet with detents.
/// The Feed tab shows every photo; each album in the Albums tab reuses this flow for its own photos.
@MainActor
final class FeedCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case grid
        case photo(id: Int)
        case viewer(id: Int)
        case comments(id: Int)
    }

    /// Where a zoom grows from. Thumbnails on different screens show the same photo, so the id includes the place too.
    enum ZoomSource: Hashable {
        case grid(Int)
        case related(parent: Int, photo: Int)
        case hero(Int)
    }

    private let title: String
    private let photos: [Photo]

    init(title: String = "Feed", photos: [Photo] = PhotoLibrary.all) {
        self.title = title
        self.photos = photos
    }

    var initialRoute: Route { .grid }

    func destination(for route: Route) -> some View {
        switch route {
        case .grid:
            FeedGridView(title: title, photos: photos, onSelect: { photo in
                self.showPhoto(id: photo.id, transition: .zoom(sourceID: ZoomSource.grid(photo.id)))
            })
        case let .photo(id):
            if let photo = PhotoLibrary.photo(id: id) {
                PhotoDetailView(viewModel: PhotoDetailViewModel(photo: photo, navigation: self))
            } else {
                ContentUnavailableView("No photo \(id)", systemImage: "photo.badge.exclamationmark")
            }
        case let .viewer(id):
            if let photo = PhotoLibrary.photo(id: id) {
                PhotoViewer(photo: photo, onClose: { self.dismissPresented() })
            }
        case let .comments(id):
            CommentsView(photoID: id, onClose: { self.dismissPresented() })
        }
    }

    func showPhoto(id: Int, transition: ScreenTransition) {
        push(.photo(id: id), transition: transition)
    }

    func open(_ link: FeedLink) {
        switch link {
        case let .photo(id): showPhoto(id: id, transition: .automatic)
        }
    }
}

extension FeedCoordinator: PhotoDetailNavigation {
    func openViewer(for photo: Photo) {
        present(
            .viewer(id: photo.id),
            as: .fullScreenCover(embedsInNavigationStack: false),
            transition: .zoom(sourceID: ZoomSource.hero(photo.id))
        )
    }

    func openComments(for photo: Photo) {
        present(.comments(id: photo.id), as: .sheet(
            detents: [.medium, .large],
            dragIndicator: .visible,
            backgroundInteraction: .enabled(upThrough: .medium)
        ))
    }

    func openRelated(_ related: Photo, from parent: Photo) {
        showPhoto(id: related.id, transition: .zoom(sourceID: ZoomSource.related(parent: parent.id, photo: related.id)))
        if LaunchOptions.simulatesDoubleTap {
            // UI tests: two taps whose actions fire in the same update, as a fast double tap can.
            showPhoto(id: related.id, transition: .zoom(sourceID: ZoomSource.related(parent: parent.id, photo: related.id)))
        }
    }
}
