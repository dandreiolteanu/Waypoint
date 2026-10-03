import SwiftUI
import Waypoint

struct FeedGridView: View {
    let photos: [Photo]
    let onSelect: (Photo) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    Button { onSelect(photo) } label: {
                        PhotoTile(photo: photo, cornerRadius: 12)
                            .aspectRatio(1, contentMode: .fit)
                            .transitionSource(id: FeedCoordinator.ZoomSource.grid(photo.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feed.photo.\(photo.id)")
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle("Feed")
    }
}

@MainActor
protocol PhotoDetailNavigation: AnyObject {
    func openViewer(for photo: Photo)
    func openComments(for photo: Photo)
    func openRelated(_ related: Photo, from parent: Photo)
}

@MainActor
@Observable
final class PhotoDetailViewModel {
    let photo: Photo
    let related: [Photo]
    var isLiked = false
    private let navigation: PhotoDetailNavigation

    init(photo: Photo, navigation: PhotoDetailNavigation) {
        self.photo = photo
        self.related = PhotoLibrary.related(to: photo)
        self.navigation = navigation
        LifetimeTracker.track(self, kind: .viewModel)
    }

    func openViewer() { navigation.openViewer(for: photo) }
    func openComments() { navigation.openComments(for: photo) }
    func open(_ related: Photo) { navigation.openRelated(related, from: photo) }
}

struct PhotoDetailView: View {
    @Bindable var viewModel: PhotoDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: viewModel.openViewer) {
                    PhotoTile(photo: viewModel.photo, cornerRadius: 20)
                        .aspectRatio(1, contentMode: .fit)
                        .transitionSource(id: FeedCoordinator.ZoomSource.hero(viewModel.photo.id))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.hero")

                HStack {
                    Text(viewModel.photo.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Like", systemImage: viewModel.isLiked ? "heart.fill" : "heart") { viewModel.isLiked.toggle() }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .tint(.pink)
                }

                Button("Comments", systemImage: "bubble.left.and.bubble.right", action: viewModel.openComments)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("detail.comments")

                Text("Related").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.related) { related in
                            Button { viewModel.open(related) } label: {
                                PhotoTile(photo: related, cornerRadius: 10)
                                    .frame(width: 88, height: 88)
                                    .transitionSource(id: FeedCoordinator.ZoomSource.related(parent: viewModel.photo.id, photo: related.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("detail.related.\(related.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle(viewModel.photo.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A chromeless full-screen viewer. It's presented without a NavigationStack, so the zoom wraps the image directly.
struct PhotoViewer: View {
    let photo: Photo
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            PhotoTile(photo: photo, cornerRadius: 0, symbolScale: 0.5)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: .infinity)
            Button("Close", systemImage: "xmark.circle.fill", action: onClose)
                .labelStyle(.iconOnly)
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.8))
                .padding()
                .accessibilityIdentifier("viewer.close")
        }
    }
}

struct CommentsView: View {
    let photoID: Int
    let onClose: () -> Void

    var body: some View {
        List {
            Section {
                Text("This sheet has medium and large detents. The background stays interactive up to medium, so you can still scroll the photo behind it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(1...12, id: \.self) { index in
                Label("Comment \(index) on photo \(photoID)", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseButton(action: onClose) }
    }
}
