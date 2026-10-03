import SwiftUI

/// A tile showing a photo's symbol on its tint. Used for thumbnails, heroes and the full-screen viewer.
struct PhotoTile: View {
    let photo: Photo
    var cornerRadius: CGFloat = 16
    var symbolScale: CGFloat = 0.4

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [photo.tint, photo.tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: photo.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: min(proxy.size.width, proxy.size.height) * symbolScale)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

/// A full-width button row used throughout the example.
struct DemoRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The toolbar close button presented screens use.
struct CloseButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Close", systemImage: "xmark", action: action)
                .accessibilityIdentifier("close")
        }
    }
}
