import Foundation
import XCTest
@testable import AppleBuildCore

final class HelperApplicationTests: XCTestCase {
    func testContainersCommandWritesTypedSuccessAndExitsZero() async throws {
        let expected = BuildContainer(
            kind: .project,
            path: "/repo/App.xcodeproj",
            label: "App.xcodeproj"
        )
        let output = OutputRecorder()
        let application = makeApplication(
            locator: StubWorkspaceLocator(result: .success([expected])),
            output: output
        )

        let status = await application.run(arguments: [
            "containers", "--workspace-root", "/repo"
        ])
        let response = try JSONDecoder().decode(
            HelperResponse<[BuildContainer]>.self,
            from: output.standardOutput
        )

        XCTAssertEqual(status, 0)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.value, [expected])
        XCTAssertEqual(response.errors, [])
        XCTAssertEqual(output.standardError, Data())
    }

    func testParserFailureWritesDomainResponseAndExitsTwo() async throws {
        let output = OutputRecorder()
        let application = makeApplication(output: output)

        let status = await application.run(arguments: ["containers"])
        let response = try JSONDecoder().decode(
            HelperResponse<String>.self,
            from: output.standardOutput
        )

        XCTAssertEqual(status, 2)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.errors, ["containers requires --workspace-root."])
        XCTAssertEqual(output.standardError, Data())
    }

    func testUnexpectedServiceFailureWritesOnlyStderrAndExitsOne() async {
        let output = OutputRecorder()
        let application = makeApplication(
            locator: StubWorkspaceLocator(result: .failure(CocoaError(.fileReadUnknown))),
            output: output
        )

        let status = await application.run(arguments: [
            "containers", "--workspace-root", "/repo"
        ])

        XCTAssertEqual(status, 1)
        XCTAssertEqual(output.standardOutput, Data())
        XCTAssertTrue(String(decoding: output.standardError, as: UTF8.self).contains(
            "AppleBuildHelper could not complete the request."
        ))
    }

    func testPrepareActionResolvesFreshChoicesBeforeReturningTypedSpecification() async throws {
        let developerDirectory = "/Applications/Xcode 27 rc.app/Contents/Developer"
        let container = BuildContainer(
            kind: .project,
            path: "/repo/App.xcodeproj",
            label: "App.xcodeproj"
        )
        let destination = Destination(
            label: "My Mac — macOS, arm64",
            specifier: "platform=macOS,arch=arm64,id=MAC-ID",
            platform: "macOS",
            id: "MAC-ID",
            generic: false
        )
        let saved = SavedBuildSelection(
            developerDirectory: developerDirectory,
            containerKind: .project,
            containerPath: container.path,
            scheme: "App",
            configuration: "Debug",
            destinationLabel: destination.label,
            destinationSpecifier: destination.specifier
        )
        let savedJSON = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        let output = OutputRecorder()
        let application = makeApplication(
            locator: StubWorkspaceLocator(result: .success([container])),
            toolchainResolver: FixedToolchainResolver(toolchain: Toolchain(
                version: "27.0",
                build: "27A266a",
                developerDirectory: developerDirectory,
                label: "Xcode 27.0, build 27A266a"
            )),
            metadataService: FixedMetadataService(
                schemes: ["App"],
                configurations: ["Debug"],
                destinations: [destination]
            ),
            output: output
        )

        for action in XcodeAction.allCases {
            output.reset()
            let status = await application.run(arguments: [
                "prepare-action", "--action", action.rawValue,
                "--workspace-root", "/repo",
                "--selection-json", savedJSON
            ])
            let response = try JSONDecoder().decode(
                HelperResponse<ProcessSpecification>.self,
                from: output.standardOutput
            )

            XCTAssertEqual(status, 0)
            XCTAssertEqual(response.value?.arguments.last, action.rawValue)
            XCTAssertEqual(response.value?.environment, ["DEVELOPER_DIR": developerDirectory])
        }
    }

    func testPrepareActionDoesNotMisreportToolLaunchFailureAsStaleSelection() async throws {
        let saved = SavedBuildSelection(
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            containerKind: nil,
            containerPath: nil,
            scheme: nil,
            configuration: nil,
            destinationLabel: nil,
            destinationSpecifier: nil
        )
        let savedJSON = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        let output = OutputRecorder()
        let application = makeApplication(
            toolchainResolver: FailingToolchainResolver(error: CocoaError(.executableNotLoadable)),
            output: output
        )

        let status = await application.run(arguments: [
            "prepare-action", "--action", "build",
            "--workspace-root", "/repo",
            "--selection-json", savedJSON
        ])

        XCTAssertEqual(status, 1)
        XCTAssertEqual(output.standardOutput, Data())
        XCTAssertTrue(String(decoding: output.standardError, as: UTF8.self).contains(
            "AppleBuildHelper could not complete the request."
        ))
    }

    func testSigningStatusCommandRequiresResolvedSelectionAndWritesTypedSnapshot() async throws {
        let developerDirectory = "/Applications/Xcode 27 rc.app/Contents/Developer"
        let container = BuildContainer(
            kind: .project,
            path: "/repo/App.xcodeproj",
            label: "App.xcodeproj"
        )
        let destination = Destination(
            label: "My Mac",
            specifier: "platform=macOS",
            platform: "macOS",
            id: nil,
            generic: true
        )
        let saved = SavedBuildSelection(
            developerDirectory: developerDirectory,
            containerKind: .project,
            containerPath: container.path,
            scheme: "App",
            configuration: "Debug",
            destinationLabel: destination.label,
            destinationSpecifier: destination.specifier
        )
        let output = OutputRecorder()
        let application = makeApplication(
            locator: StubWorkspaceLocator(result: .success([container])),
            toolchainResolver: FixedToolchainResolver(toolchain: Toolchain(
                version: "27.0",
                build: "27A266a",
                developerDirectory: developerDirectory,
                label: "Xcode 27.0, build 27A266a"
            )),
            metadataService: FixedMetadataService(
                schemes: ["App"], configurations: ["Debug"], destinations: [destination]
            ),
            signingStatusService: FixedSigningStatusService(snapshot: SigningStatusSnapshot(
                overallStatus: .warning,
                targets: []
            )),
            output: output
        )
        let savedJSON = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)

        let status = await application.run(arguments: [
            "signing-status", "--workspace-root", "/repo", "--selection-json", savedJSON
        ])
        let response = try JSONDecoder().decode(
            HelperResponse<SigningStatusSnapshot>.self,
            from: output.standardOutput
        )

        XCTAssertEqual(status, 0)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.value?.overallStatus, .warning)
    }

    func testPrepareDeviceRunResolvesSelectionAndWritesTypedPlan() async throws {
        let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
        let container = BuildContainer(kind: .project, path: "/repo/App.xcodeproj", label: "App.xcodeproj")
        let destination = Destination(
            label: "iPhone — iOS, arm64e, DEVICE",
            specifier: "platform=iOS,id=DEVICE",
            platform: "iOS",
            id: "DEVICE",
            generic: false
        )
        let saved = SavedBuildSelection(
            developerDirectory: developerDirectory,
            containerKind: .project,
            containerPath: container.path,
            scheme: "App",
            configuration: "Debug",
            destinationLabel: destination.label,
            destinationSpecifier: destination.specifier
        )
        let step = ProcessSpecification(
            command: "/usr/bin/xcrun", arguments: ["devicectl"], environment: [:], workingDirectory: "/repo"
        )
        let expected = DeviceRunPlan(
            appName: "App.app",
            bundleIdentifier: "app.example",
            deviceName: "iPhone",
            install: step,
            launch: step
        )
        let output = OutputRecorder()
        let application = makeApplication(
            locator: StubWorkspaceLocator(result: .success([container])),
            toolchainResolver: FixedToolchainResolver(toolchain: Toolchain(
                version: "27.0",
                build: "27A266a",
                developerDirectory: developerDirectory,
                label: "Xcode 27.0, build 27A266a"
            )),
            metadataService: FixedMetadataService(
                schemes: ["App"], configurations: ["Debug"], destinations: [destination]
            ),
            deviceRunService: FixedDeviceRunService(plan: expected),
            output: output
        )
        let savedJSON = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)

        let status = await application.run(arguments: [
            "prepare-device-run", "--workspace-root", "/repo", "--selection-json", savedJSON
        ])
        let response = try JSONDecoder().decode(
            HelperResponse<DeviceRunPlan>.self,
            from: output.standardOutput
        )

        XCTAssertEqual(status, 0)
        XCTAssertEqual(response.value, expected)
    }

    func testWriteConsoleDecodesStandardInputAndReturnsPath() async throws {
        let (saved, locator, toolchain, metadata) = iPhoneSelectionFixtures()
        let diagnostics = FixedDiagnosticsService(path: "/logs/console.md")
        let capture = ConsoleCapture(appName: "App", deviceName: "iPhone", startedAt: "2026-10-09T14:10:05-04:00",
                                     endedAt: nil, state: .running, lines: ["hi"], droppedLines: 0, crashSource: nil)
        let output = OutputRecorder()
        let application = makeApplication(locator: locator, toolchainResolver: toolchain, metadataService: metadata,
                                          diagnosticsService: diagnostics,
                                          standardInput: try JSONEncoder().encode(capture), output: output)

        let status = await application.run(arguments: [
            "write-console", "--workspace-root", "/repo",
            "--selection-json", String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        ])
        let response = try JSONDecoder().decode(HelperResponse<String>.self, from: output.standardOutput)

        XCTAssertEqual(status, 0)
        XCTAssertEqual(response.value, "/logs/console.md")
        XCTAssertEqual(diagnostics.lastCapture, capture)
    }

    func testWriteConsoleRejectsMalformedStandardInput() async throws {
        let (saved, locator, toolchain, metadata) = iPhoneSelectionFixtures()
        let output = OutputRecorder()
        let application = makeApplication(locator: locator, toolchainResolver: toolchain, metadataService: metadata,
                                          diagnosticsService: FixedDiagnosticsService(path: "/x"),
                                          standardInput: Data("nope".utf8), output: output)

        let status = await application.run(arguments: [
            "write-console", "--workspace-root", "/repo",
            "--selection-json", String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        ])
        let response = try JSONDecoder().decode(HelperResponse<String>.self, from: output.standardOutput)

        XCTAssertEqual(status, 2)
        XCTAssertEqual(response.errors, ["The App Console data was not readable."])
    }

    private func iPhoneSelectionFixtures() -> (
        SavedBuildSelection, StubWorkspaceLocator, FixedToolchainResolver, FixedMetadataService
    ) {
        let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
        let container = BuildContainer(kind: .project, path: "/repo/App.xcodeproj", label: "App.xcodeproj")
        let destination = Destination(
            label: "iPhone — iOS, arm64e, DEVICE",
            specifier: "platform=iOS,id=DEVICE",
            platform: "iOS",
            id: "DEVICE",
            generic: false
        )
        let saved = SavedBuildSelection(
            developerDirectory: developerDirectory,
            containerKind: .project,
            containerPath: container.path,
            scheme: "App",
            configuration: "Debug",
            destinationLabel: destination.label,
            destinationSpecifier: destination.specifier
        )
        return (
            saved,
            StubWorkspaceLocator(result: .success([container])),
            FixedToolchainResolver(toolchain: Toolchain(
                version: "27.0",
                build: "27A266a",
                developerDirectory: developerDirectory,
                label: "Xcode 27.0, build 27A266a"
            )),
            FixedMetadataService(schemes: ["App"], configurations: ["Debug"], destinations: [destination])
        )
    }

    func testWriteDocumentSavesStandardInputAsMarkdownAndReturnsThePath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WriteDocument-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let output = OutputRecorder()
        let application = makeApplication(
            logStore: LogFileStore(root: root),
            standardInput: Data("# Apple Build Command Report\n".utf8),
            output: output
        )

        let status = await application.run(arguments: ["write-document", "--app-name", "SampleApp", "--title", "Apple Build Command Report"])
        let response = try JSONDecoder().decode(HelperResponse<String>.self, from: output.standardOutput)

        XCTAssertEqual(status, 0)
        let path = try XCTUnwrap(response.value)
        XCTAssertTrue(path.hasPrefix(root.appendingPathComponent("SampleApp").path))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# Apple Build Command Report\n")
    }

    func testChooseForwardsStandardInputAndWritesTheIndex() async throws {
        let launcher = FixedChooserLauncher(index: 1)
        let output = OutputRecorder()
        let application = makeApplication(
            chooserLauncher: launcher,
            standardInput: Data(#"{"title":"T","items":["a","b"]}"#.utf8),
            output: output
        )

        let status = await application.run(arguments: ["choose", "--reader", "/ext/Reader.app"])
        let text = String(decoding: output.standardOutput, as: UTF8.self)

        XCTAssertEqual(status, 0)
        XCTAssertTrue(text.contains(#""index":1"#))
        XCTAssertEqual(launcher.received, Data(#"{"title":"T","items":["a","b"]}"#.utf8))
    }

    func testProjectNavigatorWritesTypedTreeWithoutResolvingXcode() async throws {
        let expected = ProjectNavigatorNode(
            identifier: "project:/repo/App.xcodeproj",
            name: "App",
            kind: .project,
            path: "/repo/App.xcodeproj",
            children: []
        )
        let output = OutputRecorder()
        let application = makeApplication(
            navigator: FixedProjectNavigator(tree: expected),
            output: output
        )

        let status = await application.run(arguments: [
            "project-navigator",
            "--workspace-root", "/repo",
            "--container-kind", "project",
            "--container-path", "/repo/App.xcodeproj"
        ])
        let response = try JSONDecoder().decode(
            HelperResponse<ProjectNavigatorNode>.self,
            from: output.standardOutput
        )

        XCTAssertEqual(status, 0)
        XCTAssertEqual(response.value, expected)
    }

    private func makeApplication(
        locator: any WorkspaceLocating = StubWorkspaceLocator(result: .success([])),
        toolchainResolver: any ToolchainResolving = StubToolchainResolver(),
        metadataService: any XcodeMetadataProviding = StubMetadataService(),
        signingStatusService: any SigningStatusProviding = SigningStatusService(),
        navigator: any ProjectNavigatorProviding = StubProjectNavigator(),
        deviceRunService: any DeviceRunPreparing = DeviceRunService(),
        diagnosticsService: any AppDiagnosticsProviding = AppDiagnosticsService(),
        chooserLauncher: any ChooserLaunching = ChooserLauncher(),
        logStore: LogFileStore = LogFileStore(),
        standardInput: Data = Data(),
        output: OutputRecorder
    ) -> HelperApplication {
        HelperApplication(
            locator: locator,
            toolchainResolver: toolchainResolver,
            metadataService: metadataService,
            selectionValidator: SelectionValidator(),
            buildCommandBuilder: BuildCommandBuilder(),
            signingStatusService: signingStatusService,
            deviceRunService: deviceRunService,
            diagnosticsService: diagnosticsService,
            chooserLauncher: chooserLauncher,
            logStore: logStore,
            readStandardInput: { standardInput },
            messageFormatter: UserMessageFormatter(),
            navigator: navigator,
            writeStandardOutput: output.writeStandardOutput,
            writeStandardError: output.writeStandardError
        )
    }
}

private struct FixedProjectNavigator: ProjectNavigatorProviding {
    let tree: ProjectNavigatorNode

    func projectTree(
        workspaceRoot: String,
        containerKind: ContainerKind,
        containerPath: String
    ) throws -> ProjectNavigatorNode {
        tree
    }
}

private struct FixedSigningStatusService: SigningStatusProviding {
    let snapshot: SigningStatusSnapshot

    func inspect(
        selection: BuildSelection,
        workspaceRoot: String
    ) async throws -> SigningStatusSnapshot {
        snapshot
    }
}

private struct FixedDeviceRunService: DeviceRunPreparing {
    let plan: DeviceRunPlan

    func prepare(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceRunPlan {
        plan
    }
}

private final class FixedChooserLauncher: ChooserLaunching, @unchecked Sendable {
    let index: Int?
    private let lock = NSLock()
    private var request: Data?
    init(index: Int?) { self.index = index }
    var received: Data? { lock.withLock { request } }
    func choose(readerPath: String, request: Data) async throws -> Int? {
        lock.withLock { self.request = request }
        return index
    }
}

private final class FixedDiagnosticsService: AppDiagnosticsProviding, @unchecked Sendable {
    let path: String
    private let lock = NSLock()
    private var capture: ConsoleCapture?
    init(path: String) { self.path = path }
    var lastCapture: ConsoleCapture? { lock.withLock { capture } }
    func listReports(selection: BuildSelection, workspaceRoot: String, since: Date?) async throws -> [AppReportEntry] { [] }
    func openReport(selection: BuildSelection, workspaceRoot: String, source: String) async throws -> String { path }
    func writeConsole(selection: BuildSelection, workspaceRoot: String, capture: ConsoleCapture) async throws -> String {
        lock.withLock { self.capture = capture }
        return path
    }
}

private struct StubProjectNavigator: ProjectNavigatorProviding {
    func projectTree(
        workspaceRoot: String,
        containerKind: ContainerKind,
        containerPath: String
    ) throws -> ProjectNavigatorNode {
        throw CocoaError(.fileReadUnknown)
    }
}

private struct FixedToolchainResolver: ToolchainResolving {
    let toolchain: Toolchain

    func discover(
        applicationsDirectory: String,
        savedDeveloperDirectory: String?
    ) async -> [Toolchain] {
        [toolchain]
    }

    func validate(_ developerDirectory: String) async throws -> Toolchain {
        toolchain
    }
}

private struct FailingToolchainResolver: ToolchainResolving {
    let error: any Error & Sendable

    func discover(
        applicationsDirectory: String,
        savedDeveloperDirectory: String?
    ) async -> [Toolchain] {
        []
    }

    func validate(_ developerDirectory: String) async throws -> Toolchain {
        throw error
    }
}

private struct FixedMetadataService: XcodeMetadataProviding {
    let schemes: [String]
    let configurations: [String]
    let destinations: [Destination]

    func schemes(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String] {
        schemes
    }

    func configurations(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String] {
        configurations
    }

    func destinations(
        for container: BuildContainer,
        scheme: String,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [Destination] {
        destinations
    }
}

private struct StubWorkspaceLocator: @unchecked Sendable, WorkspaceLocating {
    let result: Result<[BuildContainer], Error>

    func locate(in workspaceRoot: String) throws -> [BuildContainer] {
        try result.get()
    }
}

private struct StubToolchainResolver: ToolchainResolving {
    func discover(
        applicationsDirectory: String,
        savedDeveloperDirectory: String?
    ) async -> [Toolchain] {
        []
    }

    func validate(_ developerDirectory: String) async throws -> Toolchain {
        throw CocoaError(.fileReadUnknown)
    }
}

private struct StubMetadataService: XcodeMetadataProviding {
    func schemes(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String] {
        []
    }

    func configurations(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String] {
        []
    }

    func destinations(
        for container: BuildContainer,
        scheme: String,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [Destination] {
        []
    }
}

private final class OutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    var standardOutput: Data {
        lock.withLock { output }
    }

    var standardError: Data {
        lock.withLock { error }
    }

    func writeStandardOutput(_ data: Data) {
        lock.withLock { output.append(data) }
    }

    func writeStandardError(_ data: Data) {
        lock.withLock { error.append(data) }
    }

    func reset() {
        lock.withLock {
            output = Data()
            error = Data()
        }
    }
}
