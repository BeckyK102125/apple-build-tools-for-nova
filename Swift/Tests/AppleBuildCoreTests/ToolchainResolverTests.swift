import XCTest
@testable import AppleBuildCore

final class ToolchainResolverTests: XCTestCase {
    func testParsesXcode27RC() throws {
        XCTAssertEqual(
            try ToolchainResolver.parseVersion("Xcode 27.0\nBuild version 27A266a\n"),
            .init(version: "27.0", build: "27A266a")
        )
    }

    func testUnexpectedVersionOutputIsRejected() {
        XCTAssertThrowsError(try ToolchainResolver.parseVersion("unexpected")) { error in
            XCTAssertEqual(error.localizedDescription, "Xcode returned an unrecognized version response.")
        }
    }

    func testValidationUsesSelectedDeveloperDirectoryWithoutShell() async throws {
        let developerDirectory = "/Applications/Xcode 27 rc.app/Contents/Developer"
        let runner = RecordingProcessRunner(result: ProcessResult(
            status: 0,
            standardOutput: "Xcode 27.0\nBuild version 27A266a\n",
            standardError: ""
        ))
        let resolver = ToolchainResolver(
            processRunner: runner,
            isExecutableFile: { $0 == developerDirectory + "/usr/bin/xcodebuild" },
            applicationContents: { _ in [] }
        )

        let toolchain = try await resolver.validate(developerDirectory)
        let specifications = await runner.specifications

        XCTAssertEqual(toolchain.version, "27.0")
        XCTAssertEqual(toolchain.build, "27A266a")
        XCTAssertEqual(specifications, [ProcessSpecification(
            command: developerDirectory + "/usr/bin/xcodebuild",
            arguments: ["-version"],
            environment: ["DEVELOPER_DIR": developerDirectory],
            workingDirectory: developerDirectory
        )])
    }

    func testDiscoversXcodeApplicationsAndAddsDistinctSavedDirectory() async {
        let discovered = "/Applications/Xcode 27 rc.app/Contents/Developer"
        let saved = "/Volumes/Tools/Xcode.app/Contents/Developer"
        let runner = RecordingProcessRunner(result: ProcessResult(
            status: 0,
            standardOutput: "Xcode 27.0\nBuild version 27A266a\n",
            standardError: ""
        ))
        let resolver = ToolchainResolver(
            processRunner: runner,
            isExecutableFile: { _ in true },
            applicationContents: { _ in [
                URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
                URL(fileURLWithPath: "/Applications/Xcode 27 rc.app", isDirectory: true)
            ] }
        )

        let result = await resolver.discover(
            applicationsDirectory: "/Applications",
            savedDeveloperDirectory: saved
        )

        XCTAssertEqual(Set(result.map(\.developerDirectory)), Set([discovered, saved]))
    }

    func testInitialSelectionRequiresExactXcode27RCIdentityAndPath() {
        let expected = Toolchain(
            version: "27.0",
            build: "27A266a",
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            label: "Xcode 27.0, build 27A266a"
        )
        let wrongBuild = Toolchain(
            version: "27.0",
            build: "27A999",
            developerDirectory: expected.developerDirectory,
            label: "Wrong"
        )

        XCTAssertEqual(ToolchainResolver.verifiedInitialSelection(from: [wrongBuild, expected]), expected)
        XCTAssertNil(ToolchainResolver.verifiedInitialSelection(from: [wrongBuild]))
    }
}

private actor RecordingProcessRunner: ProcessRunning {
    private(set) var specifications: [ProcessSpecification] = []
    private let result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        specifications.append(specification)
        return result
    }
}
