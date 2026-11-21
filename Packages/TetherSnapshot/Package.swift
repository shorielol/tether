// swift-tools-version: 6.2
import PackageDescription

/// What the lock-screen widgets read. No dependencies, so the widget extension stays small.
let package = Package(
    name: "TetherSnapshot",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "TetherSnapshot", targets: ["TetherSnapshot"])],
    targets: [
        .target(name: "TetherSnapshot"),
        .testTarget(name: "TetherSnapshotTests", dependencies: ["TetherSnapshot"]),
    ]
)
