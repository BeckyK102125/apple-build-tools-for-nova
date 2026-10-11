import Foundation

/// Everything needed to put an already-built app on the chosen destination and open it:
/// optional preparation steps, an optional install, the launch, and for Mac apps an activation.
public struct DeviceRunPlan: Codable, Equatable, Sendable {
    public let kind: String
    public let appName: String
    public let bundleIdentifier: String
    public let deviceName: String
    public let steps: [ProcessSpecification]
    public let install: ProcessSpecification?
    public let launch: ProcessSpecification
    public let activate: ProcessSpecification?
    /// A line matching this pattern means the app is open; nil means it is open once launch starts.
    public let readyPattern: String?

    public init(
        kind: String = "iphone",
        appName: String,
        bundleIdentifier: String,
        deviceName: String,
        steps: [ProcessSpecification] = [],
        install: ProcessSpecification?,
        launch: ProcessSpecification,
        activate: ProcessSpecification? = nil,
        readyPattern: String? = nil
    ) {
        self.kind = kind
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.steps = steps
        self.install = install
        self.launch = launch
        self.activate = activate
        self.readyPattern = readyPattern
    }
}

/// The built app and the selected iPhone, as found by `DeviceRunService.inspect`.
public struct DeviceProduct: Equatable, Sendable {
    public let appName: String
    public let appPath: String
    public let bundleIdentifier: String
    public let deviceID: String
    public let deviceName: String
    public let developerDirectory: String
    public let workingDirectory: String
}

public struct DeviceRunError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?

    public init(_ message: String) {
        errorDescription = message
    }
}

public protocol DeviceRunPreparing: Sendable {
    func prepare(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceRunPlan
}

public struct DeviceRunService: DeviceRunPreparing, Sendable {
    private let processRunner: any ProcessRunning
    private let helperPath: String

    public init(
        processRunner: any ProcessRunning = ProcessRunner(),
        helperPath: String = Bundle.main.executablePath ?? CommandLine.arguments[0]
    ) {
        self.processRunner = processRunner
        self.helperPath = helperPath
    }

    public func prepare(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceRunPlan {
        let destination = selection.destination
        switch destination.platform {
        case "macOS":
            return try await prepareMac(selection: selection, workspaceRoot: workspaceRoot)
        case "iOS Simulator" where !destination.generic:
            return try await prepareSimulator(selection: selection, workspaceRoot: workspaceRoot)
        case "iOS" where !destination.generic:
            return try await prepareIPhone(selection: selection, workspaceRoot: workspaceRoot)
        default:
            throw DeviceRunError(
                "Build and Run needs a specific place to run: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination."
            )
        }
    }

    private func prepareIPhone(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceRunPlan {
        let product = try await inspect(selection: selection, workspaceRoot: workspaceRoot)

        func devicectl(_ arguments: [String]) -> ProcessSpecification {
            ProcessSpecification(
                command: "/usr/bin/xcrun",
                arguments: ["devicectl"] + arguments,
                environment: ["DEVELOPER_DIR": product.developerDirectory],
                workingDirectory: product.workingDirectory
            )
        }

        return DeviceRunPlan(
            kind: "iphone",
            appName: URL(fileURLWithPath: product.appPath).lastPathComponent,
            bundleIdentifier: product.bundleIdentifier,
            deviceName: product.deviceName,
            install: devicectl(["device", "install", "app", "--device", product.deviceID, product.appPath]),
            // --console keeps devicectl attached so Nova can capture the app's output.
            launch: devicectl([
                "device", "process", "launch",
                "--device", product.deviceID, "--terminate-existing", "--console", product.bundleIdentifier
            ]),
            readyPattern: #"^Launched application\b"#
        )
    }

    private func prepareMac(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceRunPlan {
        let (info, workingDirectory) = try await buildProduct(selection: selection, workspaceRoot: workspaceRoot)
        return DeviceRunPlan(
            kind: "mac",
            appName: URL(fileURLWithPath: info.appPath).lastPathComponent,
            bundleIdentifier: info.bundleIdentifier,
            deviceName: "My Mac",
            install: nil,
            // The helper opens the app through LaunchServices (one copy, in front) and streams its output.
            launch: ProcessSpecification(command: helperPath, arguments: ["mac-run", "--app", info.appPath],
                                         environment: [:], workingDirectory: workingDirectory)
        )
    }

    private func prepareSimulator(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceRunPlan {
        let destination = selection.destination
        guard let simulatorID = destination.id, !simulatorID.isEmpty, !simulatorID.hasPrefix("-"),
              simulatorID.count <= 128 else {
            throw DeviceRunError("The selected Simulator identifier is not recognized.")
        }
        let (info, workingDirectory) = try await buildProduct(selection: selection, workspaceRoot: workspaceRoot)

        func xcrun(_ arguments: [String]) -> ProcessSpecification {
            ProcessSpecification(command: "/usr/bin/xcrun", arguments: arguments,
                                 environment: ["DEVELOPER_DIR": selection.developerDirectory],
                                 workingDirectory: workingDirectory)
        }

        return DeviceRunPlan(
            kind: "simulator",
            appName: URL(fileURLWithPath: info.appPath).lastPathComponent,
            bundleIdentifier: info.bundleIdentifier,
            deviceName: Self.deviceName(from: destination.label),
            steps: [xcrun(["simctl", "bootstatus", simulatorID, "-b"])],
            install: xcrun(["simctl", "install", simulatorID, info.appPath]),
            launch: xcrun(["simctl", "launch", "--console-pty", "--terminate-running-process",
                           simulatorID, info.bundleIdentifier]),
            // Best effort after launch: Simulator.app may be installed separately or not at all
            // (it is absent from Xcode 27 on the tester's Mac); the app runs and is recorded either way.
            activate: ProcessSpecification(
                command: "/usr/bin/open",
                arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", simulatorID],
                environment: [:], workingDirectory: workingDirectory
            ),
            readyPattern: "^" + NSRegularExpression.escapedPattern(for: info.bundleIdentifier) + ": [0-9]+"
        )
    }

    /// The built app's name without ".app" (also the name its crash reports start with), for any destination.
    public func appName(selection: BuildSelection, workspaceRoot: String) async throws -> String {
        let (info, _) = try await buildProduct(selection: selection, workspaceRoot: workspaceRoot)
        return String(URL(fileURLWithPath: info.appPath).lastPathComponent.dropLast(".app".count))
    }

    private func buildProduct(selection: BuildSelection, workspaceRoot: String) async throws
        -> (ProductInfo, String) {
        // Same read-only build-settings inspection that Signing Status uses.
        let inspection = try SigningStatusService(processRunner: processRunner).makeSpecification(
            selection: selection,
            workspaceRoot: workspaceRoot
        )
        let result = try await processRunner.run(inspection)
        guard result.status == 0 else {
            throw DeviceRunError("Xcode could not report where it built the app.")
        }
        return (try Self.parseProductInfo(output: result.standardOutput), inspection.workingDirectory)
    }

    /// Finds the built app and the selected iPhone without running anything on the device.
    public func inspect(selection: BuildSelection, workspaceRoot: String) async throws -> DeviceProduct {
        let destination = selection.destination
        guard destination.platform == "iOS", !destination.generic,
              let deviceID = destination.id, !deviceID.isEmpty else {
            throw DeviceRunError(
                "Run on iPhone needs a connected iPhone. Select Destination and choose your iPhone."
            )
        }
        guard !deviceID.hasPrefix("-"), deviceID.count <= 128 else {
            throw DeviceRunError("The selected iPhone identifier is not recognized.")
        }

        // Same read-only build-settings inspection that Signing Status uses.
        let inspection = try SigningStatusService(processRunner: processRunner).makeSpecification(
            selection: selection,
            workspaceRoot: workspaceRoot
        )
        let result = try await processRunner.run(inspection)
        guard result.status == 0 else {
            throw DeviceRunError("Xcode could not report where it built the app for this iPhone.")
        }
        let product = try Self.parseProduct(output: result.standardOutput)
        let wrapper = URL(fileURLWithPath: product.appPath).lastPathComponent

        return DeviceProduct(
            appName: String(wrapper.dropLast(".app".count)),
            appPath: product.appPath,
            bundleIdentifier: product.bundleIdentifier,
            deviceID: deviceID,
            deviceName: Self.deviceName(from: destination.label),
            developerDirectory: selection.developerDirectory,
            workingDirectory: inspection.workingDirectory
        )
    }

    public static func parseProduct(output: String) throws -> (appPath: String, bundleIdentifier: String) {
        let info = try parseProductInfo(output: output)
        return (info.appPath, info.bundleIdentifier)
    }

    struct ProductInfo {
        let appPath: String
        let bundleIdentifier: String
        let executablePath: String?
    }

    static func parseProductInfo(output: String) throws -> ProductInfo {
        let failure = DeviceRunError("Xcode did not report an installable app for the selected scheme.")
        guard let data = output.data(using: .utf8),
              let records = try? JSONDecoder().decode([ProductRecord].self, from: data) else {
            throw failure
        }
        for record in records where record.buildSettings["WRAPPER_EXTENSION"] == "app" {
            guard let directory = record.buildSettings["TARGET_BUILD_DIR"], directory.hasPrefix("/"),
                  let wrapper = record.buildSettings["WRAPPER_NAME"], wrapper.hasSuffix(".app"),
                  !wrapper.contains("/"),
                  let bundleIdentifier = record.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"],
                  !bundleIdentifier.isEmpty, !bundleIdentifier.hasPrefix("-") else {
                throw failure
            }
            let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
            let appPath = directoryURL.appendingPathComponent(wrapper, isDirectory: true).standardizedFileURL.path
            var executablePath: String?
            if let relative = record.buildSettings["EXECUTABLE_PATH"], !relative.hasPrefix("/"), !relative.contains("..") {
                executablePath = directoryURL.appendingPathComponent(relative).standardizedFileURL.path
            }
            return ProductInfo(appPath: appPath, bundleIdentifier: bundleIdentifier, executablePath: executablePath)
        }
        throw failure
    }

    private static func deviceName(from label: String) -> String {
        let name = label.components(separatedBy: " — ").first ?? label
        return String(name.prefix(128))
    }
}

private struct ProductRecord: Decodable {
    let target: String
    let buildSettings: [String: String]

    private enum CodingKeys: String, CodingKey {
        case target
        case buildSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        // Keep only string settings; Xcode can emit other value types we do not need.
        let raw = try container.decode([String: LossyString].self, forKey: .buildSettings)
        buildSettings = raw.compactMapValues(\.value)
    }
}

private struct LossyString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}
