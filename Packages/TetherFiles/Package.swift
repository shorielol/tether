// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TetherFiles",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "TetherFiles", targets: ["TetherFiles"])],
    dependencies: [.package(path: "../TetherCore"), .package(path: "../WhoopProtocol")],
    targets: [
        .target(name: "TetherFiles", dependencies: ["TetherCore", "WhoopProtocol"]),
        .testTarget(name: "TetherFilesTests", dependencies: ["TetherFiles"]),
    ]
)
