import Foundation
import XCTest
@testable import AppleBuildCore

final class AppDiagnosticsServiceTests: XCTestCase {
    private var logs: URL!

    override func setUpWithError() throws {
        logs = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnostics-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: logs) }

    func testListsReportsForTheBuiltAppOnTheSelectedIPhone() async throws {
        let runner = DevicectlFake(listing: listingJSON(), report: crashText())
        let service = makeService(runner)

        let entries = try await service.listReports(selection: selection(), workspaceRoot: "/repo", since: nil)

        XCTAssertEqual(entries.map(\.source), ["Sample App-2026-10-07-063830.ips"])
        let list = try XCTUnwrap(runner.calls.first { $0.arguments.contains("files") })
        XCTAssertEqual(Array(list.arguments.prefix(8)), [
            "devicectl", "device", "info", "files", "--device", "DEVICE", "--domain-type", "systemCrashLogs"
        ])
        XCTAssertTrue(list.arguments.contains("--timeout"))
    }

    func testOpenReportValidatesSourceCopiesWritesAndCleansUp() async throws {
        let runner = DevicectlFake(listing: listingJSON(), report: crashText())
        let service = makeService(runner)

        let path = try await service.openReport(selection: selection(), workspaceRoot: "/repo",
                                                source: "Sample App-2026-10-07-063830.ips")

        XCTAssertTrue(path.hasPrefix(logs.appendingPathComponent("Sample App").path))
        let markdown = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(markdown.hasPrefix("# Crash: Sample App, October 7 at 6:38 AM"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runner.lastDestination!))

        do {
            _ = try await service.openReport(selection: selection(), workspaceRoot: "/repo", source: "../../etc/passwd")
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error.localizedDescription, "That report is no longer on your iPhone. Choose Show App Reports again.")
        }
    }

    func testUnreachableDeviceGivesOnePlainSentence() async {
        let service = makeService(DevicectlFake(listing: listingJSON(), report: "", failDevicectl: true))
        do {
            _ = try await service.listReports(selection: selection(), workspaceRoot: "/repo", since: nil)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, AppDiagnosticsService.unreachable)
        }
    }

    func testWriteConsoleIncludesCrashWhenSourceGiven() async throws {
        let service = makeService(DevicectlFake(listing: listingJSON(), report: crashText()))
        let capture = ConsoleCapture(appName: "Sample App", deviceName: "iPhone", startedAt: "2026-10-07T06:38:00-04:00",
                                     endedAt: "2026-10-07T06:38:31-04:00", state: .crashed, lines: ["hello"],
                                     droppedLines: 0, crashSource: "Sample App-2026-10-07-063830.ips")

        let path = try await service.writeConsole(selection: selection(), workspaceRoot: "/repo", capture: capture)

        let markdown = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## Crash report"))
        XCTAssertTrue(markdown.contains("Sample App crashed with EXC_BREAKPOINT"))
    }

    func testWriteConsoleStillSavesWhenTheCrashLookupFails() async throws {
        let service = makeService(DevicectlFake(listing: listingJSON(), report: crashText(), failBuildSettings: true))
        let capture = ConsoleCapture(appName: "Sample App", deviceName: "iPhone", startedAt: "2026-10-07T10:38:00Z",
                                     endedAt: "2026-10-07T10:38:31Z", state: .crashed, lines: ["hello"],
                                     droppedLines: 0, crashSource: "Sample App-2026-10-07-063830.ips")

        let path = try await service.writeConsole(selection: selection(), workspaceRoot: "/repo", capture: capture)

        let markdown = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(markdown.contains("hello"))
        XCTAssertFalse(markdown.contains("## Crash report"))
    }

    func testMacAndSimulatorReportsComeFromThisMacsDiagnosticReportsFolder() async throws {
        let local = logs.appendingPathComponent("DiagnosticReports", isDirectory: true)
        try FileManager.default.createDirectory(at: local.appendingPathComponent("Retired"), withIntermediateDirectories: true)
        try crashText().write(to: local.appendingPathComponent("Sample App-2026-10-07-063830.ips"), atomically: true, encoding: .utf8)
        try #"{"app_name":"Sample App","bug_type":"202"}"#.appending("\nCPU: 90 seconds")
            .write(to: local.appendingPathComponent("Retired/Sample App.cpu_resource-2026-10-06-120000.ips"), atomically: true, encoding: .utf8)
        try #"{"app_name":"Other","bug_type":"309"}"#.appending("\n{}")
            .write(to: local.appendingPathComponent("Other-2026-10-07-063830.ips"), atomically: true, encoding: .utf8)
        let destinations = [
            Destination(label: "My Mac — macOS, arm64e", specifier: "platform=macOS,arch=arm64e,id=MAC", platform: "macOS", id: "MAC", generic: false),
            Destination(label: "iPhone 17 — iOS Simulator 27.0, SIM", specifier: "platform=iOS Simulator,id=SIM", platform: "iOS Simulator", id: "SIM", generic: false)
        ]
        for destination in destinations {
            let runner = DevicectlFake(listing: listingJSON(), report: crashText())
            let service = AppDiagnosticsService(processRunner: runner, store: LogFileStore(root: logs),
                                                timeZone: TimeZone(identifier: "America/New_York")!, localReportsRoot: local)

            let entries = try await service.listReports(selection: selection(destination), workspaceRoot: "/repo", since: nil)
            XCTAssertEqual(entries.map(\.source), [
                "Sample App-2026-10-07-063830.ips",
                "Retired/Sample App.cpu_resource-2026-10-06-120000.ips"
            ])
            XCTAssertEqual(entries.map(\.kind), [.crash, .cpu])

            let path = try await service.openReport(selection: selection(destination), workspaceRoot: "/repo",
                                                    source: "Sample App-2026-10-07-063830.ips")
            XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8).hasPrefix("# Crash: Sample App, October 7 at 6:38 AM"))
            XCTAssertFalse(runner.calls.contains { $0.arguments.first == "devicectl" })
        }
    }

    func testGenericDestinationGetsAPlainSentenceForReports() async {
        let service = makeService(DevicectlFake(listing: listingJSON(), report: ""))
        let anyDevice = Destination(label: "Any iOS Device", specifier: "generic/platform=iOS", platform: "iOS", id: nil, generic: true)
        do {
            _ = try await service.listReports(selection: selection(anyDevice), workspaceRoot: "/repo", since: nil)
            XCTFail("Expected refusal")
        } catch {
            XCTAssertEqual(error.localizedDescription,
                           "App Reports needs a specific destination: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination.")
        }
    }

    func testGenericMacDestinationGetsAPlainSentenceForReports() async {
        let service = makeService(DevicectlFake(listing: listingJSON(), report: ""))
        let anyMac = Destination(label: "Any Mac", specifier: "generic/platform=macOS", platform: "macOS", id: nil, generic: true)
        do {
            _ = try await service.listReports(selection: selection(anyMac), workspaceRoot: "/repo", since: nil)
            XCTFail("Expected refusal")
        } catch {
            XCTAssertEqual(error.localizedDescription,
                           "App Reports needs a specific destination: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination.")
        }
    }

    // MARK: helpers

    private func makeService(_ runner: DevicectlFake) -> AppDiagnosticsService {
        AppDiagnosticsService(processRunner: runner, store: LogFileStore(root: logs),
                              timeZone: TimeZone(identifier: "America/New_York")!)
    }

    private func selection(_ destination: Destination? = nil) -> BuildSelection {
        let iPhone = Destination(label: "iPhone — iOS, arm64e, DEVICE", specifier: "platform=iOS,id=DEVICE",
                                 platform: "iOS", id: "DEVICE", generic: false)
        return BuildSelection(
            developerDirectory: "/Applications/Xcode.app/Contents/Developer",
            container: BuildContainer(kind: .project, path: "/repo/Sample.xcodeproj", label: "Sample.xcodeproj"),
            scheme: "Sample", configuration: "Debug",
            destination: destination ?? iPhone
        )
    }

    private func listingJSON() -> String {
        #"{"result":{"files":[{"relativePath":"Sample App-2026-10-07-063830.ips","metadata":{"extendedAttributes":{"bug_type":"309"}}},{"relativePath":"Other-2026-10-07-063830.ips","metadata":{"extendedAttributes":{"bug_type":"309"}}}]}}"#
    }

    private func crashText() -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try! String(contentsOf: root.appendingPathComponent("Tests/fixtures/ips-crash.ips"), encoding: .utf8)
    }
}

private final class DevicectlFake: ProcessRunning, @unchecked Sendable {
    private let listing: String
    private let report: String
    private let failDevicectl: Bool
    private let failBuildSettings: Bool
    private let lock = NSLock()
    private var recorded: [ProcessSpecification] = []
    private var destination: String?

    init(listing: String, report: String, failDevicectl: Bool = false, failBuildSettings: Bool = false) {
        self.listing = listing; self.report = report; self.failDevicectl = failDevicectl
        self.failBuildSettings = failBuildSettings
    }

    var calls: [ProcessSpecification] { lock.withLock { recorded } }
    var lastDestination: String? { lock.withLock { destination } }

    func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        lock.withLock { recorded.append(specification) }
        let arguments = specification.arguments
        if arguments.contains("-showBuildSettings") {
            if failBuildSettings { return ProcessResult(status: 65, standardOutput: "", standardError: "locked") }
            let settings = #"[{"target":"Sample App","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp/p","WRAPPER_NAME":"Sample App.app","PRODUCT_BUNDLE_IDENTIFIER":"app.example.sample"}}]"#
            return ProcessResult(status: 0, standardOutput: settings, standardError: "")
        }
        if failDevicectl { return ProcessResult(status: 1, standardOutput: "", standardError: "device locked") }
        if let index = arguments.firstIndex(of: "--json-output") {
            try Data(listing.utf8).write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        if let index = arguments.firstIndex(of: "--destination") {
            lock.withLock { destination = arguments[index + 1] }
            try Data(report.utf8).write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        return ProcessResult(status: 0, standardOutput: "", standardError: "")
    }
}
