// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TetherCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "TetherCore", targets: ["TetherCore"])],
    dependencies: [
        .package(path: "../WhoopProtocol"),
        .package(path: "../WhoopStore"),
        .package(path: "../StrandAnalytics"),
        .package(path: "../TetherSnapshot"),
    ],
    targets: [
        .target(
            name: "TetherCore",
            dependencies: ["WhoopProtocol", "WhoopStore", "StrandAnalytics", "TetherSnapshot"]
        ),
        .testTarget(name: "TetherCoreTests", dependencies: ["TetherCore", "TetherSnapshot"]),
    ]
)
