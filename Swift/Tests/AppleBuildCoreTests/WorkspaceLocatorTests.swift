import Foundation
import XCTest
@testable import AppleBuildCore

final class WorkspaceLocatorTests: XCTestCase {
    private let fileManager = FileManager.default
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? fileManager.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testWorkspacesSortBeforeProjectsAndSymlinksAreNotFollowed() throws {
        let root = temporaryDirectory.appendingPathComponent("Workspace", isDirectory: true)
        try createDirectory(root)
        try createDirectory(root.appendingPathComponent("App.xcworkspace", isDirectory: true))
        try createDirectory(root.appendingPathComponent("App.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent("Sources/Tool.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent("Pods/Dependency.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent("App.xcodeproj/Nested.xcodeproj", isDirectory: true))

        let outside = temporaryDirectory.appendingPathComponent("Outside", isDirectory: true)
        try createDirectory(outside.appendingPathComponent("External.xcodeproj", isDirectory: true))
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("OutsideLink"),
            withDestinationURL: outside
        )

        let result = try WorkspaceLocator().locate(in: root.path)

        XCTAssertEqual(result.map(\.kind), [.workspace, .project, .project])
        XCTAssertEqual(result.map(\.label), [
            "App.xcworkspace", "App.xcodeproj", "Sources/Tool.xcodeproj"
        ])
        XCTAssertFalse(result.contains { $0.path.contains("Outside") })
        XCTAssertFalse(result.contains { $0.label.contains("Nested") })
        XCTAssertFalse(result.contains { $0.label.contains("Dependency") })
    }

    func testHiddenAndGeneratedTreesAreNotDiscovered() throws {
        let root = temporaryDirectory.appendingPathComponent("Workspace", isDirectory: true)
        try createDirectory(root.appendingPathComponent("App.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent("Modules/Feature.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent(".worktrees/branch/App.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent(".svn/Checkout.xcodeproj", isDirectory: true))
        try createDirectory(
            root.appendingPathComponent(
                "build/SourcePackages/checkouts/Dependency/Dependency.xcodeproj",
                isDirectory: true
            )
        )

        let result = try WorkspaceLocator().locate(in: root.path)

        XCTAssertEqual(result.map(\.label), [
            "App.xcodeproj",
            "Modules/Feature.xcodeproj"
        ])
    }

    func testShallowerProjectSortsBeforeNestedWorkspace() throws {
        let root = temporaryDirectory.appendingPathComponent("Workspace", isDirectory: true)
        try createDirectory(root.appendingPathComponent("App.xcodeproj", isDirectory: true))
        try createDirectory(root.appendingPathComponent("Packages/Tools.xcworkspace", isDirectory: true))

        let result = try WorkspaceLocator().locate(in: root.path)

        XCTAssertEqual(result.map(\.label), [
            "App.xcodeproj",
            "Packages/Tools.xcworkspace"
        ])
    }

    func testUnavailableRootHasActionableError() {
        let missing = temporaryDirectory.appendingPathComponent("Missing").path

        XCTAssertThrowsError(try WorkspaceLocator().locate(in: missing)) { error in
            XCTAssertEqual(error.localizedDescription, "Workspace folder is unavailable.")
        }
    }

    func testFileRootHasActionableError() throws {
        let file = temporaryDirectory.appendingPathComponent("file.txt")
        try Data().write(to: file)

        XCTAssertThrowsError(try WorkspaceLocator().locate(in: file.path)) { error in
            XCTAssertEqual(error.localizedDescription, "Workspace folder is unavailable.")
        }
    }

    func testEmptyWorkspaceReturnsNoContainers() throws {
        let root = temporaryDirectory.appendingPathComponent("Empty", isDirectory: true)
        try createDirectory(root)

        XCTAssertEqual(try WorkspaceLocator().locate(in: root.path), [])
    }

    func testUnreadableNestedDirectoryIsSkippedWithoutErasingDiscoveredContainers() throws {
        let root = temporaryDirectory.appendingPathComponent("Workspace", isDirectory: true)
        let unreadable = root.appendingPathComponent("Unreadable", isDirectory: true)
        try createDirectory(root.appendingPathComponent("Visible.xcodeproj", isDirectory: true))
        try createDirectory(unreadable.appendingPathComponent("Hidden.xcodeproj", isDirectory: true))

        let locator = WorkspaceLocator(fileManager: fileManager) { directory, keys in
            if directory.standardizedFileURL == unreadable.standardizedFileURL {
                throw CocoaError(.fileReadNoPermission)
            }
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: []
            )
        }

        XCTAssertEqual(
            try locator.locate(in: root.path),
            [BuildContainer(
                kind: .project,
                path: root.appendingPathComponent("Visible.xcodeproj").path,
                label: "Visible.xcodeproj"
            )]
        )
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
