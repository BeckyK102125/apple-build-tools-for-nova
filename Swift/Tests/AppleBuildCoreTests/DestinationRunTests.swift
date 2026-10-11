import Foundation
import XCTest
@testable import AppleBuildCore

final class DestinationRunTests: XCTestCase {
    private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"

    func testMacRunAsksTheHelperToOpenTheAppAndStreamItsOutput() async throws {
        let runner = SettingsRunner(output: #"[{"target":"Poster","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp/DD/Build/Products/Debug","WRAPPER_NAME":"Poster.app","EXECUTABLE_PATH":"Poster.app/Contents/MacOS/Poster","PRODUCT_BUNDLE_IDENTIFIER":"app.example.poster"}}]"#)
        let myMac = Destination(label: "My Mac — generic macOS destination", specifier: "platform=macOS",
                                platform: "macOS", id: nil, generic: true)

        let plan = try await DeviceRunService(processRunner: runner, helperPath: "/ext/Executables/AppleBuildHelper")
            .prepare(selection: selection(myMac), workspaceRoot: "/repo")

        XCTAssertEqual(plan.kind, "mac")
        XCTAssertEqual(plan.deviceName, "My Mac")
        XCTAssertEqual(plan.steps, [])
        XCTAssertNil(plan.install)
        // The helper opens the app through LaunchServices (one copy, in front) and streams its output.
        XCTAssertEqual(plan.launch, ProcessSpecification(
            command: "/ext/Executables/AppleBuildHelper",
            arguments: ["mac-run", "--app", "/tmp/DD/Build/Products/Debug/Poster.app"],
            environment: [:], workingDirectory: "/repo"
        ))
        XCTAssertNil(plan.activate)
        XCTAssertNil(plan.readyPattern)
    }

    func testSimulatorRunBootsShowsInstallsAndLaunchesWithConsole() async throws {
        let runner = SettingsRunner(output: #"[{"target":"Poster","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp/DD/Build/Products/Debug-iphonesimulator","WRAPPER_NAME":"Poster.app","PRODUCT_BUNDLE_IDENTIFIER":"app.example.poster"}}]"#)
        let simulator = Destination(label: "iPhone 17 — iOS Simulator 27.0, SIM-1", specifier: "platform=iOS Simulator,id=SIM-1",
                                    platform: "iOS Simulator", id: "SIM-1", generic: false)

        let plan = try await DeviceRunService(processRunner: runner).prepare(selection: selection(simulator), workspaceRoot: "/repo")

        func xcrun(_ arguments: [String]) -> ProcessSpecification {
            ProcessSpecification(command: "/usr/bin/xcrun", arguments: arguments,
                                 environment: ["DEVELOPER_DIR": developerDirectory], workingDirectory: "/repo")
        }
        XCTAssertEqual(plan.kind, "simulator")
        XCTAssertEqual(plan.deviceName, "iPhone 17")
        XCTAssertEqual(plan.steps, [xcrun(["simctl", "bootstatus", "SIM-1", "-b"])])
        // Showing the Simulator window is best effort after launch: the app runs even if Simulator.app is absent.
        XCTAssertEqual(plan.activate, ProcessSpecification(command: "/usr/bin/open",
                                                           arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", "SIM-1"],
                                                           environment: [:], workingDirectory: "/repo"))
        XCTAssertEqual(plan.install, xcrun(["simctl", "install", "SIM-1", "/tmp/DD/Build/Products/Debug-iphonesimulator/Poster.app"]))
        XCTAssertEqual(plan.launch, xcrun(["simctl", "launch", "--console-pty", "--terminate-running-process", "SIM-1", "app.example.poster"]))
        XCTAssertEqual(plan.readyPattern, #"^app\.example\.poster: [0-9]+"#)
    }

    func testGenericDestinationIsRefusedInPlainWordsWithoutRunningXcode() async {
        let runner = SettingsRunner(output: "[]")
        let anyDevice = Destination(label: "Any iOS Device — generic iOS device", specifier: "generic/platform=iOS",
                                    platform: "iOS", id: nil, generic: true)
        do {
            _ = try await DeviceRunService(processRunner: runner).prepare(selection: selection(anyDevice), workspaceRoot: "/repo")
            XCTFail("Expected refusal")
        } catch {
            XCTAssertEqual(error.localizedDescription,
                           "Build and Run needs a specific place to run: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination.")
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    private func selection(_ destination: Destination) -> BuildSelection {
        BuildSelection(
            developerDirectory: developerDirectory,
            container: BuildContainer(kind: .project, path: "/repo/Poster.xcodeproj", label: "Poster.xcodeproj"),
            scheme: "Poster", configuration: "Debug", destination: destination
        )
    }
}

private final class SettingsRunner: ProcessRunning, @unchecked Sendable {
    private let output: String
    private let lock = NSLock()
    private var recorded: [ProcessSpecification] = []
    init(output: String) { self.output = output }
    var calls: [ProcessSpecification] { lock.withLock { recorded } }
    func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        lock.withLock { recorded.append(specification) }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }
}
