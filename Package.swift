// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Grid",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GridCore"),
        .executableTarget(name: "Grid", dependencies: ["GridCore"]),
        .testTarget(name: "GridCoreTests", dependencies: ["GridCore"]),
    ],
    swiftLanguageModes: [.v5]
)
