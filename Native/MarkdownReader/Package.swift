// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownReader",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MarkdownReader", targets: ["MarkdownReader"])],
    targets: [
        .target(name: "MarkdownReaderCore"),
        .executableTarget(name: "MarkdownReader", dependencies: ["MarkdownReaderCore"]),
        .testTarget(name: "MarkdownReaderCoreTests", dependencies: ["MarkdownReaderCore"])
    ]
)
