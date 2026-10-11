import Foundation

public protocol HelperDomainFailure: LocalizedError {}

public enum HelperCommand: Equatable, Sendable {
    case toolchains(applications: String, savedDeveloperDirectory: String?)
    case containers(workspaceRoot: String)
    case schemes(
        workspaceRoot: String,
        developerDirectory: String,
        containerKind: ContainerKind,
        containerPath: String
    )
    case configurations(
        workspaceRoot: String,
        developerDirectory: String,
        containerKind: ContainerKind,
        containerPath: String
    )
    case destinations(
        workspaceRoot: String,
        developerDirectory: String,
        containerKind: ContainerKind,
        containerPath: String,
        scheme: String
    )
    case prepareAction(action: XcodeAction, workspaceRoot: String, selectionJSON: String)
    case signingStatus(workspaceRoot: String, selectionJSON: String)
    case prepareDeviceRun(workspaceRoot: String, selectionJSON: String)
    case appReports(workspaceRoot: String, selectionJSON: String, sinceEpoch: Int?)
    case appReport(workspaceRoot: String, selectionJSON: String, source: String)
    case writeConsole(workspaceRoot: String, selectionJSON: String)
    case choose(readerPath: String)
    case macRun(appPath: String)
    case writeDocument(appName: String, title: String)
    case currentSelection(workspaceRoot: String, selectionJSON: String)
    case projectNavigator(
        workspaceRoot: String,
        containerKind: ContainerKind,
        containerPath: String
    )

    public static func parse(arguments: [String]) throws -> HelperCommand {
        guard let commandName = arguments.first else {
            throw HelperProtocolError("No helper command was supplied.")
        }

        switch commandName {
        case "toolchains":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: ["--applications", "--saved-developer-directory"]
            )
            let applications = try options.required("--applications")
            try requireAbsolutePath(applications, option: "--applications")
            if let saved = options.optional("--saved-developer-directory") {
                try requireAbsolutePath(saved, option: "--saved-developer-directory")
            }
            return .toolchains(
                applications: applications,
                savedDeveloperDirectory: options.optional("--saved-developer-directory")
            )

        case "containers":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: ["--workspace-root"]
            )
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            return .containers(workspaceRoot: workspaceRoot)

        case "schemes", "configurations":
            let options = try containerOptions(command: commandName, arguments: Array(arguments.dropFirst()))
            let workspaceRoot = try options.required("--workspace-root")
            let developerDirectory = try options.required("--developer-directory")
            let containerPath = try options.required("--container-path")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            try requireAbsolutePath(developerDirectory, option: "--developer-directory")
            try requireAbsolutePath(containerPath, option: "--container-path")
            let kind = try containerKind(options.required("--container-kind"))

            if commandName == "schemes" {
                return .schemes(
                    workspaceRoot: workspaceRoot,
                    developerDirectory: developerDirectory,
                    containerKind: kind,
                    containerPath: containerPath
                )
            }
            return .configurations(
                workspaceRoot: workspaceRoot,
                developerDirectory: developerDirectory,
                containerKind: kind,
                containerPath: containerPath
            )

        case "destinations":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: [
                    "--workspace-root", "--developer-directory", "--container-kind",
                    "--container-path", "--scheme"
                ]
            )
            let workspaceRoot = try options.required("--workspace-root")
            let developerDirectory = try options.required("--developer-directory")
            let containerPath = try options.required("--container-path")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            try requireAbsolutePath(developerDirectory, option: "--developer-directory")
            try requireAbsolutePath(containerPath, option: "--container-path")
            return .destinations(
                workspaceRoot: workspaceRoot,
                developerDirectory: developerDirectory,
                containerKind: try containerKind(options.required("--container-kind")),
                containerPath: containerPath,
                scheme: try options.required("--scheme")
            )

        case "prepare-action":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: ["--action", "--workspace-root", "--selection-json"]
            )
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            let selectionJSON = try options.required("--selection-json")
            let rawAction = try options.required("--action")
            guard let action = XcodeAction(rawValue: rawAction) else {
                throw HelperProtocolError("--action must be build, clean, or test.")
            }
            return .prepareAction(
                action: action,
                workspaceRoot: workspaceRoot,
                selectionJSON: selectionJSON
            )

        case "current-selection":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: ["--workspace-root", "--selection-json"]
            )
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            return .currentSelection(
                workspaceRoot: workspaceRoot,
                selectionJSON: try options.required("--selection-json")
            )

        case "signing-status", "prepare-device-run":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: ["--workspace-root", "--selection-json"]
            )
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            if commandName == "prepare-device-run" {
                return .prepareDeviceRun(
                    workspaceRoot: workspaceRoot,
                    selectionJSON: try options.required("--selection-json")
                )
            }
            return .signingStatus(
                workspaceRoot: workspaceRoot,
                selectionJSON: try options.required("--selection-json")
            )

        case "app-reports":
            let options = try ParsedOptions(command: commandName, arguments: Array(arguments.dropFirst()),
                                            allowed: ["--workspace-root", "--selection-json", "--since-epoch"])
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            var since: Int?
            if let raw = options.optional("--since-epoch") {
                guard let value = Int(raw), value >= 0 else {
                    throw HelperProtocolError("--since-epoch must be a whole number of seconds.")
                }
                since = value
            }
            return .appReports(workspaceRoot: workspaceRoot, selectionJSON: try options.required("--selection-json"), sinceEpoch: since)

        case "app-report":
            let options = try ParsedOptions(command: commandName, arguments: Array(arguments.dropFirst()),
                                            allowed: ["--workspace-root", "--selection-json", "--source"])
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            let source = try options.required("--source")
            guard !source.hasPrefix("/"), !source.contains(".."), source.hasSuffix(".ips") else {
                throw HelperProtocolError("--source must be a report name from Show App Reports.")
            }
            return .appReport(workspaceRoot: workspaceRoot, selectionJSON: try options.required("--selection-json"), source: source)

        case "write-console":
            let options = try ParsedOptions(command: commandName, arguments: Array(arguments.dropFirst()),
                                            allowed: ["--workspace-root", "--selection-json"])
            let workspaceRoot = try options.required("--workspace-root")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            return .writeConsole(workspaceRoot: workspaceRoot, selectionJSON: try options.required("--selection-json"))

        case "write-document":
            let options = try ParsedOptions(command: commandName, arguments: Array(arguments.dropFirst()),
                                            allowed: ["--app-name", "--title"])
            return .writeDocument(appName: try options.required("--app-name"), title: try options.required("--title"))

        case "mac-run":
            let options = try ParsedOptions(command: commandName, arguments: Array(arguments.dropFirst()),
                                            allowed: ["--app"])
            let app = try options.required("--app")
            try requireAbsolutePath(app, option: "--app")
            guard app.hasSuffix(".app") else {
                throw HelperProtocolError("--app must be a built Mac app.")
            }
            return .macRun(appPath: app)

        case "choose":
            let options = try ParsedOptions(command: commandName, arguments: Array(arguments.dropFirst()),
                                            allowed: ["--reader"])
            let reader = try options.required("--reader")
            try requireAbsolutePath(reader, option: "--reader")
            guard reader.hasSuffix(".app") else {
                throw HelperProtocolError("--reader must be the bundled reader app.")
            }
            return .choose(readerPath: reader)

        case "project-navigator":
            let options = try ParsedOptions(
                command: commandName,
                arguments: Array(arguments.dropFirst()),
                allowed: ["--workspace-root", "--container-kind", "--container-path"]
            )
            let workspaceRoot = try options.required("--workspace-root")
            let containerPath = try options.required("--container-path")
            try requireAbsolutePath(workspaceRoot, option: "--workspace-root")
            try requireAbsolutePath(containerPath, option: "--container-path")
            return .projectNavigator(
                workspaceRoot: workspaceRoot,
                containerKind: try containerKind(options.required("--container-kind")),
                containerPath: containerPath
            )

        default:
            throw HelperProtocolError("Unknown helper command \(commandName).")
        }
    }

    private static func containerOptions(command: String, arguments: [String]) throws -> ParsedOptions {
        try ParsedOptions(
            command: command,
            arguments: arguments,
            allowed: [
                "--workspace-root", "--developer-directory", "--container-kind", "--container-path"
            ]
        )
    }

    private static func containerKind(_ rawValue: String) throws -> ContainerKind {
        guard let kind = ContainerKind(rawValue: rawValue) else {
            throw HelperProtocolError("--container-kind must be workspace or project.")
        }
        return kind
    }

    private static func requireAbsolutePath(_ path: String, option: String) throws {
        guard (path as NSString).isAbsolutePath else {
            throw HelperProtocolError("\(option) must be an absolute path.")
        }
    }
}

public enum JSONEmitter {
    public static func encode<Value: Codable>(_ response: HelperResponse<Value>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(response)
    }
}

private struct ParsedOptions {
    let command: String
    let values: [String: String]

    init(command: String, arguments: [String], allowed: Set<String>) throws {
        self.command = command
        var values: [String: String] = [:]
        var index = 0

        while index < arguments.count {
            let option = arguments[index]
            guard option.hasPrefix("--") else {
                throw HelperProtocolError("Unexpected argument \(option) for \(command).")
            }
            guard allowed.contains(option) else {
                throw HelperProtocolError("Unknown option \(option) for \(command).")
            }
            guard values[option] == nil else {
                throw HelperProtocolError("Option \(option) was provided more than once for \(command).")
            }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw HelperProtocolError("\(option) requires a value for \(command).")
            }

            values[option] = arguments[index + 1]
            index += 2
        }

        self.values = values
    }

    func required(_ option: String) throws -> String {
        guard let value = values[option], !value.isEmpty else {
            throw HelperProtocolError("\(command) requires \(option).")
        }
        return value
    }

    func optional(_ option: String) -> String? {
        values[option]
    }
}

private struct HelperProtocolError: HelperDomainFailure {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
