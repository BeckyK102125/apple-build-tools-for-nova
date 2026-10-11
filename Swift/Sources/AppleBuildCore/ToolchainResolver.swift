import Foundation

public struct XcodeVersion: Equatable, Sendable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }
}

public protocol ToolchainResolving: Sendable {
    func discover(
        applicationsDirectory: String,
        savedDeveloperDirectory: String?
    ) async -> [Toolchain]
    func validate(_ developerDirectory: String) async throws -> Toolchain
}

public struct ToolchainResolver: ToolchainResolving {
    public static let initialDeveloperDirectory = "/Applications/Xcode 27 rc.app/Contents/Developer"
    public static let initialVersion = "27.0"
    public static let initialBuild = "27A266a"

    private let processRunner: any ProcessRunning
    private let isExecutableFile: @Sendable (String) -> Bool
    private let applicationContents: @Sendable (URL) throws -> [URL]

    public init(
        processRunner: any ProcessRunning = ProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.processRunner = processRunner
        let sendableFileManager = SendableFileManager(fileManager)
        isExecutableFile = { sendableFileManager.value.isExecutableFile(atPath: $0) }
        applicationContents = { directory in
            try sendableFileManager.value.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        }
    }

    init(
        processRunner: any ProcessRunning,
        isExecutableFile: @escaping @Sendable (String) -> Bool,
        applicationContents: @escaping @Sendable (URL) throws -> [URL]
    ) {
        self.processRunner = processRunner
        self.isExecutableFile = isExecutableFile
        self.applicationContents = applicationContents
    }

    public func discover(
        applicationsDirectory: String,
        savedDeveloperDirectory: String?
    ) async -> [Toolchain] {
        let applicationsURL = URL(
            fileURLWithPath: applicationsDirectory,
            isDirectory: true
        ).standardizedFileURL
        let applications = (try? applicationContents(applicationsURL)) ?? []
        var candidates = applications.compactMap { application -> String? in
            let name = application.lastPathComponent
            guard name.hasPrefix("Xcode"), application.pathExtension.lowercased() == "app" else {
                return nil
            }
            return application
                .appendingPathComponent("Contents/Developer", isDirectory: true)
                .standardizedFileURL.path
        }

        if let savedDeveloperDirectory, !savedDeveloperDirectory.isEmpty {
            candidates.append(
                URL(fileURLWithPath: savedDeveloperDirectory, isDirectory: true).standardizedFileURL.path
            )
        }

        var seen: Set<String> = []
        var toolchains: [Toolchain] = []
        for candidate in candidates where seen.insert(candidate).inserted {
            if let toolchain = try? await validate(candidate) {
                toolchains.append(toolchain)
            }
        }

        return toolchains.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    public func validate(_ developerDirectory: String) async throws -> Toolchain {
        guard (developerDirectory as NSString).isAbsolutePath else {
            throw ToolchainResolverError("The Xcode developer directory must be an absolute path.")
        }

        let standardizedDirectory = URL(
            fileURLWithPath: developerDirectory,
            isDirectory: true
        ).standardizedFileURL.path
        let xcodebuild = standardizedDirectory + "/usr/bin/xcodebuild"
        guard isExecutableFile(xcodebuild) else {
            throw ToolchainResolverError("The selected Xcode developer directory is unavailable.")
        }

        let result = try await processRunner.run(ProcessSpecification(
            command: xcodebuild,
            arguments: ["-version"],
            environment: ["DEVELOPER_DIR": standardizedDirectory],
            workingDirectory: standardizedDirectory
        ))
        guard result.status == 0 else {
            throw ToolchainResolverError("The selected Xcode could not report its version.")
        }

        let parsed = try Self.parseVersion(result.standardOutput)
        return Toolchain(
            version: parsed.version,
            build: parsed.build,
            developerDirectory: standardizedDirectory,
            label: "Xcode \(parsed.version), build \(parsed.build) — \(standardizedDirectory)"
        )
    }

    public static func parseVersion(_ output: String) throws -> XcodeVersion {
        let lines = output
            .split(whereSeparator: \Character.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count == 2,
              lines[0].hasPrefix("Xcode "),
              lines[1].hasPrefix("Build version ") else {
            throw ToolchainResolverError("Xcode returned an unrecognized version response.")
        }

        let version = String(lines[0].dropFirst("Xcode ".count))
        let build = String(lines[1].dropFirst("Build version ".count))
        guard !version.isEmpty, !build.isEmpty else {
            throw ToolchainResolverError("Xcode returned an unrecognized version response.")
        }
        return XcodeVersion(version: version, build: build)
    }

    public static func verifiedInitialSelection(from toolchains: [Toolchain]) -> Toolchain? {
        toolchains.first {
            $0.version == initialVersion
                && $0.build == initialBuild
                && $0.developerDirectory == initialDeveloperDirectory
        }
    }
}

private struct ToolchainResolverError: HelperDomainFailure {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
