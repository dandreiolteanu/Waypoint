// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Waypoint",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Waypoint", targets: ["Waypoint"])
    ],
    targets: [
        .target(name: "Waypoint"),
        .testTarget(name: "WaypointTests", dependencies: ["Waypoint"])
    ],
    swiftLanguageModes: [.v6]
)
