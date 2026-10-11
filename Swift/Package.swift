// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleBuildTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppleBuildCore", targets: ["AppleBuildCore"]),
        .executable(name: "AppleBuildHelper", targets: ["AppleBuildHelper"])
    ],
    targets: [
        .target(name: "AppleBuildCore"),
        .executableTarget(name: "AppleBuildHelper", dependencies: ["AppleBuildCore"]),
        .testTarget(name: "AppleBuildCoreTests", dependencies: ["AppleBuildCore"])
    ]
)
