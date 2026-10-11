import Foundation
import XCTest
@testable import AppleBuildCore

final class XcodeMetadataServiceTests: XCTestCase {
    func testParsesProjectSchemesAndConfigurations() throws {
        let fixture = try fixture(named: "project-list-xcode-27.json")

        XCTAssertEqual(try XcodeMetadataService.parseSchemes(from: fixture), ["BuildFixture"])
        XCTAssertEqual(
            try XcodeMetadataService.parseProjectConfigurations(from: fixture),
            ["Debug", "Release"]
        )
    }

    func testParsesWorkspaceSchemes() throws {
        let fixture = try fixture(named: "workspace-list-xcode-27.json")

        XCTAssertEqual(try XcodeMetadataService.parseSchemes(from: fixture), ["BuildFixture"])
    }

    func testParsesOnlyEligibleMacPhoneAndSpecificSimulatorDestinations() throws {
        let fixture = try fixture(named: "destinations-xcode-27.txt")

        XCTAssertEqual(try XcodeMetadataService.parseDestinations(from: fixture), [
            Destination(
                label: "My Mac — macOS, arm64",
                specifier: "platform=macOS,arch=arm64,id=MAC-ID",
                platform: "macOS",
                id: "MAC-ID",
                generic: false
            ),
            Destination(
                label: "Any iOS Device — generic iOS device",
                specifier: "generic/platform=iOS",
                platform: "iOS",
                id: nil,
                generic: true
            ),
            Destination(
                label: "Sam's iPhone — iOS, arm64, PHONE-A",
                specifier: "platform=iOS,id=PHONE-A",
                platform: "iOS",
                id: "PHONE-A",
                generic: false
            ),
            Destination(
                label: "Any Mac — generic macOS destination",
                specifier: "platform=macOS",
                platform: "macOS",
                id: nil,
                generic: true
            ),
            Destination(
                label: "iPhone 17 — iOS Simulator 27.0, SIM-A",
                specifier: "platform=iOS Simulator,id=SIM-A",
                platform: "iOS Simulator",
                id: "SIM-A",
                generic: false
            ),
            Destination(
                label: "iPhone 18 Pro — iOS Simulator, SIM-B",
                specifier: "platform=iOS Simulator,id=SIM-B",
                platform: "iOS Simulator",
                id: "SIM-B",
                generic: false
            )
        ])
    }

    func testProjectSchemeCommandUsesExactToolchainContainerAndWorkspaceRoot() async throws {
        let output = try fixture(named: "project-list-xcode-27.json")
        let runner = RecordingMetadataRunner(results: [ProcessResult(
            status: 0,
            standardOutput: output,
            standardError: ""
        )])
        let service = XcodeMetadataService(processRunner: runner)
        let developerDirectory = "/Applications/Xcode 27 rc.app/Contents/Developer"
        let container = BuildContainer(
            kind: .project,
            path: "/repo/Build Fixture.xcodeproj",
            label: "Build Fixture.xcodeproj"
        )

        let schemes = try await service.schemes(
            for: container,
            workspaceRoot: "/repo",
            developerDirectory: developerDirectory
        )
        let specifications = await runner.specifications

        XCTAssertEqual(schemes, ["BuildFixture"])
        XCTAssertEqual(specifications, [ProcessSpecification(
            command: developerDirectory + "/usr/bin/xcodebuild",
            arguments: ["-project", container.path, "-list", "-json"],
            environment: ["DEVELOPER_DIR": developerDirectory],
            workingDirectory: "/repo"
        )])
    }

    func testDestinationCommandIncludesSchemeAndShowDestinations() async throws {
        let output = try fixture(named: "destinations-xcode-27.txt")
        let runner = RecordingMetadataRunner(results: [ProcessResult(
            status: 0,
            standardOutput: output,
            standardError: ""
        )])
        let service = XcodeMetadataService(processRunner: runner)
        let developerDirectory = "/Applications/Xcode 27 rc.app/Contents/Developer"
        let container = BuildContainer(
            kind: .workspace,
            path: "/repo/App.xcworkspace",
            label: "App.xcworkspace"
        )

        _ = try await service.destinations(
            for: container,
            scheme: "BuildFixture",
            workspaceRoot: "/repo",
            developerDirectory: developerDirectory
        )
        let specifications = await runner.specifications

        XCTAssertEqual(specifications.first?.arguments, [
            "-workspace", container.path,
            "-scheme", "BuildFixture",
            "-showdestinations"
        ])
    }

    func testWorkspaceConfigurationsAreCaseSensitiveIntersectionOfReferencedProjects() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("App.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try #"<Workspace><FileRef location="group:One.xcodeproj"/><FileRef location="container:Nested/Two.xcodeproj"/></Workspace>"#
            .write(
                to: workspace.appendingPathComponent("contents.xcworkspacedata"),
                atomically: true,
                encoding: .utf8
            )
        let runner = RecordingMetadataRunner(results: [
            ProcessResult(
                status: 0,
                standardOutput: #"{"project":{"configurations":["Debug","Release"]}}"#,
                standardError: ""
            ),
            ProcessResult(
                status: 0,
                standardOutput: #"{"project":{"configurations":["Release","release","Profile"]}}"#,
                standardError: ""
            )
        ])
        let service = XcodeMetadataService(processRunner: runner)
        let container = BuildContainer(
            kind: .workspace,
            path: workspace.path,
            label: "App.xcworkspace"
        )

        let result = try await service.configurations(
            for: container,
            workspaceRoot: root.path,
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer"
        )

        XCTAssertEqual(result, ["Release"])
        let specifications = await runner.specifications
        XCTAssertEqual(specifications.map(\.arguments), [
            ["-project", root.appendingPathComponent("One.xcodeproj").path, "-list", "-json"],
            ["-project", root.appendingPathComponent("Nested/Two.xcodeproj").path, "-list", "-json"]
        ])
    }

    func testWorkspaceProjectReferenceOutsideActiveRootIsRejected() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("Root", isDirectory: true)
        let workspace = root.appendingPathComponent("App.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try #"<Workspace><FileRef location="group:../Outside.xcodeproj"/></Workspace>"#
            .write(
                to: workspace.appendingPathComponent("contents.xcworkspacedata"),
                atomically: true,
                encoding: .utf8
            )
        let service = XcodeMetadataService(processRunner: RecordingMetadataRunner(results: []))
        let container = BuildContainer(
            kind: .workspace,
            path: workspace.path,
            label: "App.xcworkspace"
        )

        do {
            _ = try await service.configurations(
                for: container,
                workspaceRoot: root.path,
                developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer"
            )
            XCTFail("Expected an outside-workspace error.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "A project referenced by the selected workspace is outside the active workspace."
            )
        }
    }

    func testParsingFailureRetainsFullProcessResultAndReportsOnlyFinalTwentyLines() async throws {
        let output = (1...25).map { "line \($0)" }.joined(separator: "\n")
        let processResult = ProcessResult(status: 0, standardOutput: output, standardError: "")
        let service = XcodeMetadataService(
            processRunner: RecordingMetadataRunner(results: [processResult])
        )
        let container = BuildContainer(
            kind: .project,
            path: "/repo/App.xcodeproj",
            label: "App.xcodeproj"
        )

        do {
            _ = try await service.schemes(
                for: container,
                workspaceRoot: "/repo",
                developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer"
            )
            XCTFail("Expected a parsing error.")
        } catch let error as XcodeMetadataOperationError {
            XCTAssertEqual(error.processResult, processResult)
            XCTAssertTrue(error.localizedDescription.contains("Scheme discovery could not be parsed."))
            XCTAssertTrue(error.localizedDescription.contains("line 25"))
            XCTAssertFalse(error.localizedDescription.contains("line 5\n"))
        }
    }

    private func fixture(named name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Tests/fixtures/\(name)"),
            encoding: .utf8
        )
    }
}

private actor RecordingMetadataRunner: ProcessRunning {
    private(set) var specifications: [ProcessSpecification] = []
    private var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        specifications.append(specification)
        guard !results.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }
        return results.removeFirst()
    }
}
