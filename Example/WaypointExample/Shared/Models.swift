import SwiftUI

struct User: Hashable, Sendable {
    var name: String
    var email: String
    var favoriteColor: ProfileColor
    var interests: Set<Interest>
}

enum ProfileColor: String, CaseIterable, Identifiable, Sendable {
    case indigo, teal, orange, pink, mint

    var id: Self { self }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .teal: .teal
        case .orange: .orange
        case .pink: .pink
        case .mint: .mint
        }
    }

    var title: String { rawValue.capitalized }
}

enum Interest: String, CaseIterable, Identifiable, Sendable {
    case travel, food, architecture, nature, street

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct Photo: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let symbol: String
    let tint: Color
    let caption: String
}

enum PhotoLibrary {
    static let all: [Photo] = {
        let symbols = ["mountain.2.fill", "sun.horizon.fill", "leaf.fill", "building.columns.fill", "tram.fill", "fish.fill",
                       "camera.macro", "tree.fill", "cloud.sun.fill", "sailboat.fill", "bicycle", "flame.fill",
                       "moon.stars.fill", "drop.fill", "snowflake", "bird.fill", "tortoise.fill", "globe.europe.africa.fill"]
        let tints: [Color] = [.indigo, .orange, .green, .brown, .blue, .teal, .pink, .mint, .cyan, .purple, .red, .yellow]
        return symbols.enumerated().map { index, symbol in
            Photo(
                id: index + 1,
                title: symbol.split(separator: ".").first.map { $0.capitalized } ?? "Photo",
                symbol: symbol,
                tint: tints[index % tints.count],
                caption: "Shot #\(index + 1). Tap the image to open it full screen, or swipe back to shrink it into the grid."
            )
        }
    }()

    static func photo(id: Int) -> Photo? {
        all.first { $0.id == id }
    }

    static func related(to photo: Photo) -> [Photo] {
        all.filter { $0.id != photo.id && ($0.id % 3 == photo.id % 3) }
    }
}

/// The albums in the iPad split view. Each one is a slice of the photo library.
enum Album: String, CaseIterable, Identifiable, Hashable, Sendable {
    case landscapes, city, nature, sky

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .landscapes: "mountain.2"
        case .city: "building.2"
        case .nature: "leaf"
        case .sky: "cloud.sun"
        }
    }

    var photos: [Photo] {
        let index = Album.allCases.firstIndex(of: self) ?? 0
        return PhotoLibrary.all.filter { $0.id % Album.allCases.count == index }
    }
}
