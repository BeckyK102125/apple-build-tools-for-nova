import Foundation
import XCTest
@testable import AppleBuildCore

final class ProjectNavigatorServiceTests: XCTestCase {
    func testLoadsExplicitGroupsInXcodeOrderAndResolvesPaths() throws {
        let fixture = try ProjectFixture(
            projectName: "App",
            projectFile: explicitGroupsProject,
            files: [
                "Sources/Second.swift": "struct Second {}",
                "Sources/First.swift": "struct First {}"
            ]
        )
        defer { fixture.remove() }

        let tree = try ProjectNavigatorService().projectTree(
            workspaceRoot: fixture.root.path,
            containerKind: .project,
            containerPath: fixture.project.path
        )

        XCTAssertEqual(tree.name, "App")
        XCTAssertEqual(tree.kind, .project)
        XCTAssertEqual(tree.children.map(\.name), ["Sources"])
        XCTAssertEqual(tree.children[0].children.map(\.name), ["Second.swift", "First.swift"])
        XCTAssertEqual(
            tree.children[0].children.map(\.path),
            [
                fixture.root.appendingPathComponent("Sources/Second.swift").path,
                fixture.root.appendingPathComponent("Sources/First.swift").path
            ]
        )
    }

    func testEnumeratesXcode27SynchronizedGroupsFolderFirstAndFiltersHiddenBuildContent() throws {
        let fixture = try ProjectFixture(
            projectName: "Synced",
            projectFile: synchronizedGroupProject,
            files: [
                "Synced/Zeta.swift": "struct Zeta {}",
                "Synced/Alpha.swift": "struct Alpha {}",
                "Synced/build": "This is a source artifact, not a generated directory.",
                "Synced/Models/Model.swift": "struct Model {}",
                "Synced/.secret.swift": "",
                "Synced/.build/generated.swift": ""
            ]
        )
        defer { fixture.remove() }

        let tree = try ProjectNavigatorService().projectTree(
            workspaceRoot: fixture.root.path,
            containerKind: .project,
            containerPath: fixture.project.path
        )

        XCTAssertEqual(tree.children.map(\.name), ["Synced"])
        XCTAssertEqual(tree.children[0].children.map(\.name), ["Models", "Alpha.swift", "build", "Zeta.swift"])
        XCTAssertEqual(tree.children[0].children[0].children.map(\.name), ["Model.swift"])
    }

    func testSynchronizedGroupUsesDeterministicTieBreakerForEquivalentNames() throws {
        let fixture = try ProjectFixture(
            projectName: "Sorted",
            projectFile: synchronizedGroupProject,
            files: [:]
        )
        defer { fixture.remove() }
        let synced = fixture.root.appendingPathComponent("Synced", isDirectory: true)
        try FileManager.default.createDirectory(at: synced, withIntermediateDirectories: true)
        try "full width".write(
            to: synced.appendingPathComponent("Ａ.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "ascii".write(
            to: synced.appendingPathComponent("A.swift"),
            atomically: true,
            encoding: .utf8
        )

        let tree = try ProjectNavigatorService().projectTree(
            workspaceRoot: fixture.root.path,
            containerKind: .project,
            containerPath: fixture.project.path
        )

        XCTAssertEqual(tree.children[0].children.map(\.name), ["A.swift", "Ａ.swift"])
        XCTAssertTrue(projectNavigatorNamePrecedes("Foo.swift", "foo.swift"))
        XCTAssertFalse(projectNavigatorNamePrecedes("foo.swift", "Foo.swift"))
    }

    func testExcludesProductsAndSDKReferences() throws {
        let fixture = try ProjectFixture(
            projectName: "Filtered",
            projectFile: filteredReferencesProject,
            files: ["Source.swift": "struct Source {}"]
        )
        defer { fixture.remove() }

        let tree = try ProjectNavigatorService().projectTree(
            workspaceRoot: fixture.root.path,
            containerKind: .project,
            containerPath: fixture.project.path
        )

        XCTAssertEqual(tree.children.map(\.name), ["Source.swift"])
    }

    func testExcludesHiddenGeneratedAndExternalExplicitGroups() throws {
        let fixture = try ProjectFixture(
            projectName: "FilteredGroups",
            projectFile: filteredGroupsProject,
            files: [
                "Source.swift": "struct Source {}",
                "build": "This is a source artifact, not a generated directory.",
                ".Hidden/Secret.swift": "struct Secret {}",
                "DerivedData/Generated.swift": "struct Generated {}",
                ".private/Private.swift": "struct Private {}"
            ]
        )
        defer { fixture.remove() }

        let tree = try ProjectNavigatorService().projectTree(
            workspaceRoot: fixture.root.path,
            containerKind: .project,
            containerPath: fixture.project.path
        )

        XCTAssertEqual(tree.children.map(\.name), ["Source.swift", "build"])
    }

    func testRejectsWorkspaceUntilWorkspaceNavigationIsImplemented() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Navigator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("App.xcworkspace", isDirectory: true)

        XCTAssertThrowsError(try ProjectNavigatorService().projectTree(
            workspaceRoot: root.path,
            containerKind: .workspace,
            containerPath: workspace.path
        )) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Project Navigator currently supports selected Xcode projects, not workspaces. Select Project or Workspace and choose a project."
            )
        }
    }

    func testRejectsProjectSymlinkThatEscapesTheNovaWorkspace() throws {
        let external = try ProjectFixture(
            projectName: "External",
            projectFile: synchronizedGroupProject,
            files: ["Synced/File.swift": "struct File {}"]
        )
        defer { external.remove() }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("Navigator-Workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let linkedProject = workspace.appendingPathComponent("External.xcodeproj")
        try FileManager.default.createSymbolicLink(
            atPath: linkedProject.path,
            withDestinationPath: external.project.path
        )

        XCTAssertThrowsError(try ProjectNavigatorService().projectTree(
            workspaceRoot: workspace.path,
            containerKind: .project,
            containerPath: linkedProject.path
        )) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected Xcode project is outside the current Nova workspace."
            )
        }
    }

    func testRejectsProjectFileSymlinkThatEscapesTheNovaWorkspace() throws {
        let fixture = try ProjectFixture(
            projectName: "LinkedFile",
            projectFile: filteredReferencesProject,
            files: ["Source.swift": "struct Source {}"]
        )
        defer { fixture.remove() }
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Navigator-External-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        let externalProjectFile = externalDirectory.appendingPathComponent("project.pbxproj")
        try filteredReferencesProject.write(to: externalProjectFile, atomically: true, encoding: .utf8)

        let internalProjectFile = fixture.project.appendingPathComponent("project.pbxproj")
        try FileManager.default.removeItem(at: internalProjectFile)
        try FileManager.default.createSymbolicLink(
            atPath: internalProjectFile.path,
            withDestinationPath: externalProjectFile.path
        )

        XCTAssertThrowsError(try ProjectNavigatorService().projectTree(
            workspaceRoot: fixture.root.path,
            containerKind: .project,
            containerPath: fixture.project.path
        )) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected Xcode project file is outside the current Nova workspace."
            )
        }
    }
}

private struct ProjectFixture {
    let root: URL
    let project: URL

    init(projectName: String, projectFile: String, files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Navigator-\(UUID().uuidString)", isDirectory: true)
        project = root.appendingPathComponent("\(projectName).xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try projectFile.write(
            to: project.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )
        for (relativePath, contents) in files {
            let file = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private let explicitGroupsProject = #"""
// !$*UTF8*$!
{
  objects = {
    ROOT = { isa = PBXProject; mainGroup = MAIN; productRefGroup = PRODUCTS; };
    MAIN = { isa = PBXGroup; children = ( SOURCES, PRODUCTS, ); sourceTree = "<group>"; };
    SOURCES = { isa = PBXGroup; children = ( SECOND, FIRST, ); path = Sources; sourceTree = "<group>"; };
    SECOND = { isa = PBXFileReference; path = Second.swift; sourceTree = "<group>"; };
    FIRST = { isa = PBXFileReference; path = First.swift; sourceTree = "<group>"; };
    PRODUCTS = { isa = PBXGroup; children = ( PRODUCT, ); name = Products; sourceTree = "<group>"; };
    PRODUCT = { isa = PBXFileReference; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
  };
  rootObject = ROOT;
}
"""#

private let synchronizedGroupProject = #"""
// !$*UTF8*$!
{
  objects = {
    ROOT = { isa = PBXProject; mainGroup = MAIN; };
    MAIN = { isa = PBXGroup; children = ( SYNCED, ); sourceTree = "<group>"; };
    SYNCED = { isa = PBXFileSystemSynchronizedRootGroup; path = Synced; sourceTree = "<group>"; };
  };
  rootObject = ROOT;
}
"""#

private let filteredReferencesProject = #"""
// !$*UTF8*$!
{
  objects = {
    ROOT = { isa = PBXProject; mainGroup = MAIN; productRefGroup = PRODUCTS; };
    MAIN = { isa = PBXGroup; children = ( SOURCE, FRAMEWORKS, PRODUCTS, ); sourceTree = "<group>"; };
    SOURCE = { isa = PBXFileReference; path = Source.swift; sourceTree = "<group>"; };
    FRAMEWORKS = { isa = PBXGroup; children = ( SDK, ); name = Frameworks; sourceTree = "<group>"; };
    SDK = { isa = PBXFileReference; path = System/Library/Frameworks/AppKit.framework; sourceTree = SDKROOT; };
    PRODUCTS = { isa = PBXGroup; children = ( PRODUCT, ); name = Products; sourceTree = "<group>"; };
    PRODUCT = { isa = PBXFileReference; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
  };
  rootObject = ROOT;
}
"""#

private let filteredGroupsProject = #"""
// !$*UTF8*$!
{
  objects = {
    ROOT = { isa = PBXProject; mainGroup = MAIN; };
    MAIN = { isa = PBXGroup; children = ( SOURCE, BUILD_FILE, HIDDEN, GENERATED, PRIVATE, SDK, PRODUCTS, ); sourceTree = "<group>"; };
    SOURCE = { isa = PBXFileReference; path = Source.swift; sourceTree = "<group>"; };
    BUILD_FILE = { isa = PBXFileReference; path = build; sourceTree = "<group>"; };
    HIDDEN = { isa = PBXGroup; children = ( SECRET, ); path = .Hidden; sourceTree = "<group>"; };
    SECRET = { isa = PBXFileReference; path = Secret.swift; sourceTree = "<group>"; };
    GENERATED = { isa = PBXGroup; children = ( GENERATED_FILE, ); path = DerivedData; sourceTree = "<group>"; };
    GENERATED_FILE = { isa = PBXFileReference; path = Generated.swift; sourceTree = "<group>"; };
    PRIVATE = { isa = PBXFileReference; path = .private/Private.swift; sourceTree = "<group>"; };
    SDK = { isa = PBXGroup; children = ( SDK_FILE, ); path = System/Library/Frameworks; sourceTree = SDKROOT; };
    SDK_FILE = { isa = PBXFileReference; path = AppKit.framework; sourceTree = "<group>"; };
    PRODUCTS = { isa = PBXGroup; children = ( PRODUCT, ); path = Products; sourceTree = BUILT_PRODUCTS_DIR; };
    PRODUCT = { isa = PBXFileReference; path = App.app; sourceTree = "<group>"; };
  };
  rootObject = ROOT;
}
"""#
