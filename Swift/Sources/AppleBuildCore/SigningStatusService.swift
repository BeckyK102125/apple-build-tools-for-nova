import Foundation

public enum SigningStatus: String, Codable, Equatable, Sendable {
    case ready
    case warning
    case unavailable
    case error
}

public struct SigningTargetStatus: Codable, Equatable, Sendable {
    public let targetName: String
    public let bundleIdentifier: String?
    public let signingStyle: String?
    public let developmentTeam: String?
    public let signingIdentity: String?
    public let signingAllowed: Bool?
    public let signingRequired: Bool?
    public let provisioningProfile: String?
    public let entitlements: String?
    public let sdkRoot: String?
    public let status: SigningStatus

    public init(
        targetName: String,
        bundleIdentifier: String?,
        signingStyle: String?,
        developmentTeam: String?,
        signingIdentity: String?,
        signingAllowed: Bool?,
        signingRequired: Bool?,
        provisioningProfile: String?,
        entitlements: String?,
        sdkRoot: String?,
        status: SigningStatus
    ) {
        self.targetName = targetName
        self.bundleIdentifier = bundleIdentifier
        self.signingStyle = signingStyle
        self.developmentTeam = developmentTeam
        self.signingIdentity = signingIdentity
        self.signingAllowed = signingAllowed
        self.signingRequired = signingRequired
        self.provisioningProfile = provisioningProfile
        self.entitlements = entitlements
        self.sdkRoot = sdkRoot
        self.status = status
    }
}

public struct SigningStatusSnapshot: Codable, Equatable, Sendable {
    public let overallStatus: SigningStatus
    public let targets: [SigningTargetStatus]

    public init(overallStatus: SigningStatus, targets: [SigningTargetStatus]) {
        self.overallStatus = overallStatus
        self.targets = targets
    }
}

public struct SigningStatusError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?

    public init(_ message: String) {
        errorDescription = message
    }
}

public protocol SigningStatusProviding: Sendable {
    func inspect(
        selection: BuildSelection,
        workspaceRoot: String
    ) async throws -> SigningStatusSnapshot
}

public struct SigningStatusService: SigningStatusProviding, Sendable {
    private let processRunner: any ProcessRunning

    public init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    public func inspect(
        selection: BuildSelection,
        workspaceRoot: String
    ) async throws -> SigningStatusSnapshot {
        let result = try await processRunner.run(
            try makeSpecification(selection: selection, workspaceRoot: workspaceRoot)
        )
        guard result.status == 0 else {
            throw SigningStatusError("Signing status inspection failed.")
        }
        return try Self.parse(output: result.standardOutput)
    }

    public func makeSpecification(
        selection: BuildSelection,
        workspaceRoot: String
    ) throws -> ProcessSpecification {
        guard (workspaceRoot as NSString).isAbsolutePath,
              (selection.developerDirectory as NSString).isAbsolutePath else {
            throw SigningStatusError("The signing status paths must be absolute.")
        }

        let root = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            .standardizedFileURL.path
        let container = URL(fileURLWithPath: selection.container.path)
            .standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard container == root || container.hasPrefix(prefix) else {
            throw SigningStatusError(
                "The selected project or workspace is outside the active workspace."
            )
        }

        let containerArguments: [String]
        switch selection.container.kind {
        case .workspace:
            containerArguments = ["-workspace", container]
        case .project:
            containerArguments = ["-project", container]
        }

        return ProcessSpecification(
            command: "/usr/bin/xcrun",
            arguments: ["xcodebuild"] + containerArguments + [
                "-scheme", selection.scheme,
                "-configuration", selection.configuration,
                "-destination", selection.destination.specifier,
                "-showBuildSettings", "-json"
            ],
            environment: ["DEVELOPER_DIR": selection.developerDirectory],
            workingDirectory: root
        )
    }

    public static func parse(output: String) throws -> SigningStatusSnapshot {
        guard let data = output.data(using: .utf8) else {
            throw SigningStatusError("Xcode returned unrecognized signing build settings.")
        }

        let records: [RawSigningRecord]
        do {
            records = try JSONDecoder().decode([RawSigningRecord].self, from: data)
        } catch {
            throw SigningStatusError("Xcode returned unrecognized signing build settings.")
        }
        guard !records.isEmpty, records.count <= 64 else {
            throw SigningStatusError("Xcode returned unrecognized signing build settings.")
        }

        let targets = records.map(makeTargetStatus)
        let overall: SigningStatus
        if targets.allSatisfy({ $0.status == .unavailable }) {
            overall = .unavailable
        } else if targets.contains(where: { $0.status == .error }) {
            overall = .error
        } else if targets.contains(where: { $0.status == .warning }) {
            overall = .warning
        } else if targets.contains(where: { $0.status == .unavailable }) {
            overall = .warning
        } else {
            overall = .ready
        }
        return SigningStatusSnapshot(overallStatus: overall, targets: targets)
    }

    private static func makeTargetStatus(_ record: RawSigningRecord) -> SigningTargetStatus {
        let settings = record.buildSettings
        let allowed = bool(settings["CODE_SIGNING_ALLOWED"])
        let required = bool(settings["CODE_SIGNING_REQUIRED"])
        let team = bounded(string(settings["DEVELOPMENT_TEAM"]), max: 128)
        let identity = bounded(string(settings["CODE_SIGN_IDENTITY"]), max: 256)
        let style = bounded(string(settings["CODE_SIGN_STYLE"]), max: 64)
        let profile = sanitizeProfile(string(settings["PROVISIONING_PROFILE_SPECIFIER"]))
        let targetStatus: SigningStatus
        if allowed == false {
            targetStatus = .unavailable
        } else if allowed == true && !isEmpty(team) && !isEmpty(identity)
                    && (style?.caseInsensitiveCompare("manual") != .orderedSame || profile != nil) {
            targetStatus = .ready
        } else {
            targetStatus = .warning
        }

        return SigningTargetStatus(
            targetName: bounded(record.target, max: 128) ?? "Unnamed target",
            bundleIdentifier: bounded(string(settings["PRODUCT_BUNDLE_IDENTIFIER"]), max: 256),
            signingStyle: style,
            developmentTeam: team,
            signingIdentity: identity,
            signingAllowed: allowed,
            signingRequired: required,
            provisioningProfile: profile,
            entitlements: sanitizeRelativePath(string(settings["CODE_SIGN_ENTITLEMENTS"])),
            sdkRoot: bounded(string(settings["SDKROOT"]), max: 128),
            status: targetStatus
        )
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case let .string(value)? = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: JSONValue?) -> Bool? {
        guard let value = string(value) else { return nil }
        switch value.uppercased() {
        case "YES", "TRUE", "1": return true
        case "NO", "FALSE", "0": return false
        default: return nil
        }
    }

    private static func bounded(_ value: String?, max: Int) -> String? {
        guard let value else { return nil }
        return String(value.prefix(max))
    }

    private static func isEmpty(_ value: String?) -> Bool {
        value == nil || value?.isEmpty == true
    }

    private static func sanitizeRelativePath(_ value: String?) -> String? {
        guard let value, !value.hasPrefix("/"), !value.contains("/Users/") else { return nil }
        return bounded(value, max: 256)
    }

    private static func sanitizeProfile(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.hasPrefix("/") || value.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, options: .regularExpression) != nil {
            return "Configured"
        }
        return bounded(value, max: 256)
    }
}

private struct RawSigningRecord: Decodable {
    let target: String
    let buildSettings: [String: JSONValue]
}

private enum JSONValue: Decodable {
    case string(String)
    case number
    case boolean
    case object
    case array
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if (try? container.decode(Double.self)) != nil {
            self = .number
        } else if (try? container.decode(Bool.self)) != nil {
            self = .boolean
        } else if (try? container.decode([JSONValue].self)) != nil {
            self = .array
        } else if (try? container.decode([String: JSONValue].self)) != nil {
            self = .object
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }
}
