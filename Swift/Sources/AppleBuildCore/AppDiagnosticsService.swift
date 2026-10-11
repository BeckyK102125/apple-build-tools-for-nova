import Foundation

public protocol AppDiagnosticsProviding: Sendable {
    func listReports(selection: BuildSelection, workspaceRoot: String, since: Date?) async throws -> [AppReportEntry]
    func openReport(selection: BuildSelection, workspaceRoot: String, source: String) async throws -> String
    func writeConsole(selection: BuildSelection, workspaceRoot: String, capture: ConsoleCapture) async throws -> String
}

public struct AppDiagnosticsError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct AppDiagnosticsService: AppDiagnosticsProviding, Sendable {
    public static let unreachable = "Your iPhone is not reachable. Unlock it, connect it, and make sure it trusts this Mac."

    public static let defaultLocalReportsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)

    private let processRunner: any ProcessRunning
    private let store: LogFileStore
    private let timeZone: TimeZone
    private let localReportsRoot: URL

    public init(processRunner: any ProcessRunning = ProcessRunner(), store: LogFileStore = LogFileStore(),
                timeZone: TimeZone = .current, localReportsRoot: URL = AppDiagnosticsService.defaultLocalReportsRoot) {
        self.processRunner = processRunner; self.store = store; self.timeZone = timeZone
        self.localReportsRoot = localReportsRoot
    }

    /// Where reports for the chosen destination live: the iPhone itself, or this Mac's DiagnosticReports
    /// folder for Mac apps and Simulator apps (Simulator apps run as Mac processes).
    private enum Source {
        case iPhone(DeviceProduct)
        case thisMac(appName: String)

        var appName: String {
            switch self {
            case let .iPhone(product): return product.appName
            case let .thisMac(appName): return appName
            }
        }
    }

    private func source(selection: BuildSelection, workspaceRoot: String) async throws -> Source {
        let destination = selection.destination
        let runs = DeviceRunService(processRunner: processRunner)
        switch destination.platform {
        case "iOS" where !destination.generic:
            return .iPhone(try await runs.inspect(selection: selection, workspaceRoot: workspaceRoot))
        case "macOS" where !destination.generic, "iOS Simulator" where !destination.generic:
            return .thisMac(appName: try await runs.appName(selection: selection, workspaceRoot: workspaceRoot))
        default:
            throw AppDiagnosticsError(
                "App Reports needs a specific destination: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination."
            )
        }
    }

    public func listReports(selection: BuildSelection, workspaceRoot: String, since: Date?) async throws -> [AppReportEntry] {
        let source = try await source(selection: selection, workspaceRoot: workspaceRoot)
        return try AppReportListing.parse(json: try await listing(source), appName: source.appName,
                                          timeZone: timeZone, since: since)
    }

    public func openReport(selection: BuildSelection, workspaceRoot: String, source path: String) async throws -> String {
        let source = try await source(selection: selection, workspaceRoot: workspaceRoot)
        let entry = try await entry(for: path, source: source)
        let report = try await readReport(entry.source, source: source)
        let markdown = DiagnosticsMarkdown.report(report, label: entry.label)
        return try store.write(appName: source.appName, title: entry.label.replacingOccurrences(of: ",", with: ""), contents: markdown)
    }

    public func writeConsole(selection: BuildSelection, workspaceRoot: String, capture: ConsoleCapture) async throws -> String {
        var crash: IPSReport?
        // A crash section is a bonus; a locked or disconnected phone must not lose the console itself.
        if let path = capture.crashSource,
           let source = try? await source(selection: selection, workspaceRoot: workspaceRoot),
           let entry = try? await entry(for: path, source: source) {
            crash = try? await readReport(entry.source, source: source)
        }
        return try store.write(appName: capture.appName, title: "App Console",
                               contents: DiagnosticsMarkdown.console(capture, crash: crash))
    }

    private func entry(for path: String, source: Source) async throws -> AppReportEntry {
        let all = try AppReportListing.parse(json: try await listing(source), appName: source.appName,
                                             timeZone: timeZone, limit: nil)
        guard let entry = all.first(where: { $0.source == path }) else {
            if case .iPhone = source {
                throw AppDiagnosticsError("That report is no longer on your iPhone. Choose Show App Reports again.")
            }
            throw AppDiagnosticsError("That report is no longer on this Mac. Choose Show App Reports again.")
        }
        return entry
    }

    private func listing(_ source: Source) async throws -> Data {
        switch source {
        case let .iPhone(product): return try await listing(product)
        case let .thisMac(appName): return try localListing(appName: appName)
        }
    }

    private func readReport(_ path: String, source: Source) async throws -> IPSReport {
        switch source {
        case let .iPhone(product):
            return try await copyReport(path, product: product)
        case .thisMac:
            // `path` was matched against a fresh listing of this folder, so it cannot escape it.
            let text = try String(contentsOf: localReportsRoot.appendingPathComponent(path), encoding: .utf8)
            return try IPSReport.parse(text)
        }
    }

    /// Builds the same listing shape devicectl returns, from this Mac's report folder and its Retired folder,
    /// reading only the first line of this app's reports to learn their kind.
    private func localListing(appName: String) throws -> Data {
        var files: [[String: Any]] = []
        for folder in ["", "Retired"] {
            let directory = folder.isEmpty ? localReportsRoot : localReportsRoot.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names where name.hasPrefix(appName) && name.hasSuffix(".ips") {
                let relative = folder.isEmpty ? name : folder + "/" + name
                var attributes: [String: String] = [:]
                if let bugType = Self.headerBugType(directory.appendingPathComponent(name)) {
                    attributes["bug_type"] = bugType
                }
                files.append(["relativePath": relative, "metadata": ["extendedAttributes": attributes]])
            }
        }
        return try JSONSerialization.data(withJSONObject: ["result": ["files": files]])
    }

    private static func headerBugType(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        guard let line = head.split(separator: 10, maxSplits: 1).first,
              let header = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return nil }
        return header["bug_type"] as? String
    }

    private func listing(_ product: DeviceProduct) async throws -> Data {
        try await withTemporaryFolder { folder in
            let output = folder.appendingPathComponent("files.json")
            try await runDevicectl(product, ["device", "info", "files", "--device", product.deviceID,
                                             "--domain-type", "systemCrashLogs", "--timeout", "30",
                                             "--json-output", output.path])
            return try Data(contentsOf: output)
        }
    }

    private func copyReport(_ source: String, product: DeviceProduct) async throws -> IPSReport {
        try await withTemporaryFolder { folder in
            let destination = folder.appendingPathComponent("report.ips")
            try await runDevicectl(product, ["device", "copy", "from", "--device", product.deviceID,
                                             "--domain-type", "systemCrashLogs", "--source", source,
                                             "--destination", destination.path, "--timeout", "30"])
            let text = try String(contentsOf: destination, encoding: .utf8)
            return try IPSReport.parse(text)
        }
    }

    private func runDevicectl(_ product: DeviceProduct, _ arguments: [String]) async throws {
        let result = try await processRunner.run(ProcessSpecification(
            command: "/usr/bin/xcrun", arguments: ["devicectl"] + arguments,
            environment: ["DEVELOPER_DIR": product.developerDirectory],
            workingDirectory: product.workingDirectory
        ))
        guard result.status == 0 else { throw AppDiagnosticsError(Self.unreachable) }
    }

    private func withTemporaryFolder<T>(_ body: (URL) async throws -> T) async throws -> T {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleBuildTools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await body(folder)
    }
}
