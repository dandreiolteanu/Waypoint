// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Waypoint",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Waypoint", targets: ["Waypoint"])
    ],
    targets: [
        .target(name: "Waypoint"),
        .testTarget(name: "WaypointTests", dependencies: ["Waypoint"])
    ],
    swiftLanguageModes: [.v6]
)
