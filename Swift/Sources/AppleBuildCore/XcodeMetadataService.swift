import Foundation

public protocol XcodeMetadataProviding: Sendable {
    func schemes(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String]
    func configurations(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String]
    func destinations(
        for container: BuildContainer,
        scheme: String,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [Destination]
}

public struct XcodeMetadataService: XcodeMetadataProviding {
    private let processRunner: any ProcessRunning
    private let readFile: @Sendable (URL) throws -> String

    public init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
        readFile = { try String(contentsOf: $0, encoding: .utf8) }
    }

    init(
        processRunner: any ProcessRunning,
        readFile: @escaping @Sendable (URL) throws -> String
    ) {
        self.processRunner = processRunner
        self.readFile = readFile
    }

    public func schemes(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String] {
        let result = try await runList(
            container: container,
            workspaceRoot: workspaceRoot,
            developerDirectory: developerDirectory
        )
        return try parse(
            operation: "Scheme discovery",
            result: result,
            parser: Self.parseSchemes(from:)
        )
    }

    public func configurations(
        for container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [String] {
        switch container.kind {
        case .project:
            let result = try await runList(
                container: container,
                workspaceRoot: workspaceRoot,
                developerDirectory: developerDirectory
            )
            return try parse(
                operation: "Configuration discovery",
                result: result,
                parser: Self.parseProjectConfigurations(from:)
            )

        case .workspace:
            let projects = try referencedProjects(
                by: container,
                within: workspaceRoot
            )
            var sharedConfigurations: [String]?
            for project in projects {
                let result = try await runList(
                    container: project,
                    workspaceRoot: workspaceRoot,
                    developerDirectory: developerDirectory
                )
                let configurations = try parse(
                    operation: "Workspace configuration discovery",
                    result: result,
                    parser: Self.parseProjectConfigurations(from:)
                )
                if let current = sharedConfigurations {
                    let next = Set(configurations)
                    sharedConfigurations = current.filter(next.contains)
                } else {
                    sharedConfigurations = configurations
                }
            }

            guard let sharedConfigurations, !sharedConfigurations.isEmpty else {
                throw XcodeMetadataOperationError(
                    "No build configuration is shared by every project in the selected workspace."
                )
            }
            return sharedConfigurations
        }
    }

    public func destinations(
        for container: BuildContainer,
        scheme: String,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> [Destination] {
        let result = try await processRunner.run(ProcessSpecification(
            command: developerDirectory + "/usr/bin/xcodebuild",
            arguments: containerArguments(container) + [
                "-scheme", scheme, "-showdestinations"
            ],
            environment: ["DEVELOPER_DIR": developerDirectory],
            workingDirectory: workspaceRoot
        ))
        return try parse(
            operation: "Destination discovery",
            result: result,
            parser: Self.parseDestinations(from:)
        )
    }

    public static func parseSchemes(from output: String) throws -> [String] {
        let metadata = try decodeList(output)
        guard let details = metadata.project ?? metadata.workspace else {
            throw XcodeMetadataOperationError("Xcode returned unrecognized list metadata.")
        }
        return details.schemes ?? []
    }

    public static func parseProjectConfigurations(from output: String) throws -> [String] {
        let metadata = try decodeList(output)
        guard let project = metadata.project else {
            throw XcodeMetadataOperationError("Xcode returned no project configurations.")
        }
        return project.configurations ?? []
    }

    public static func parseDestinations(from output: String) throws -> [Destination] {
        var isReadingAvailableDestinations = false
        var foundAvailableHeading = false
        var destinations: [Destination] = []

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Available destinations for")
                || line.hasPrefix("Destinations compatible with") {
                foundAvailableHeading = true
                isReadingAvailableDestinations = true
                continue
            }
            if line.hasPrefix("Ineligible destinations for")
                || line.hasPrefix("Destinations incompatible with") {
                isReadingAvailableDestinations = false
                continue
            }
            guard isReadingAvailableDestinations, line.hasPrefix("{"), line.hasSuffix("}") else {
                continue
            }

            let fields = destinationFields(line)
            guard let platform = fields["platform"], let name = fields["name"] else {
                throw XcodeMetadataOperationError("Xcode returned an unrecognized destination response.")
            }
            guard platform == "macOS" || platform == "iOS" || platform == "iOS Simulator" else {
                continue
            }
            if fields["variant"] == "Mac Catalyst" {
                continue
            }

            if platform == "iOS Simulator" {
                guard let id = fields["id"], !id.isEmpty, !id.contains("Placeholder") else {
                    continue
                }
                let osSuffix = fields["OS"].flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
                destinations.append(Destination(
                    label: "\(name) — iOS Simulator\(osSuffix), \(id)",
                    specifier: "platform=iOS Simulator,id=\(id)",
                    platform: platform,
                    id: id,
                    generic: false
                ))
                continue
            }

            let architecture = fields["arch"]
            let rawID = fields["id"]
            let isGeneric = platform == "iOS" && (rawID?.contains("Placeholder") == true)
            if isGeneric {
                destinations.append(Destination(
                    label: "\(name) — generic iOS device",
                    specifier: "generic/platform=iOS",
                    platform: platform,
                    id: nil,
                    generic: true
                ))
                continue
            }
            if platform == "macOS", rawID == nil || rawID == "" {
                destinations.append(Destination(
                    label: "\(name) — generic macOS destination",
                    specifier: "platform=macOS",
                    platform: platform,
                    id: nil,
                    generic: true
                ))
                continue
            }

            guard let id = rawID, !id.isEmpty else {
                throw XcodeMetadataOperationError("Xcode returned an eligible destination without an identifier.")
            }

            if platform == "macOS" {
                var description = [platform]
                if let architecture, !architecture.isEmpty {
                    description.append(architecture)
                }
                var specifier = "platform=macOS"
                if let architecture, !architecture.isEmpty {
                    specifier += ",arch=\(architecture)"
                }
                specifier += ",id=\(id)"
                destinations.append(Destination(
                    label: "\(name) — \(description.joined(separator: ", "))",
                    specifier: specifier,
                    platform: platform,
                    id: id,
                    generic: false
                ))
            } else {
                var description = [platform]
                if let architecture, !architecture.isEmpty {
                    description.append(architecture)
                }
                description.append(id)
                destinations.append(Destination(
                    label: "\(name) — \(description.joined(separator: ", "))",
                    specifier: "platform=iOS,id=\(id)",
                    platform: platform,
                    id: id,
                    generic: false
                ))
            }
        }

        guard foundAvailableHeading else {
            throw XcodeMetadataOperationError("Xcode returned an unrecognized destination response.")
        }
        return destinations
    }

    private func runList(
        container: BuildContainer,
        workspaceRoot: String,
        developerDirectory: String
    ) async throws -> ProcessResult {
        try await processRunner.run(ProcessSpecification(
            command: developerDirectory + "/usr/bin/xcodebuild",
            arguments: containerArguments(container) + ["-list", "-json"],
            environment: ["DEVELOPER_DIR": developerDirectory],
            workingDirectory: workspaceRoot
        ))
    }

    private func parse<Value>(
        operation: String,
        result: ProcessResult,
        parser: (String) throws -> Value
    ) throws -> Value {
        let combinedOutput = [result.standardOutput, result.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard result.status == 0 else {
            throw XcodeMetadataOperationError(
                "\(operation) failed.\(diagnosticSuffix(combinedOutput))",
                processResult: result
            )
        }
        do {
            return try parser(result.standardOutput)
        } catch {
            throw XcodeMetadataOperationError(
                "\(operation) could not be parsed.\(diagnosticSuffix(combinedOutput))",
                processResult: result
            )
        }
    }

    private func referencedProjects(
        by workspace: BuildContainer,
        within workspaceRoot: String
    ) throws -> [BuildContainer] {
        let root = URL(fileURLWithPath: workspaceRoot, isDirectory: true).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let contentsURL = URL(fileURLWithPath: workspace.path, isDirectory: true)
            .appendingPathComponent("contents.xcworkspacedata")
        let contents = try readFile(contentsURL)
        let pattern = "location\\s*=\\s*\"(?:group|container):([^\"#?]+\\.xcodeproj)\""
        let regularExpression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        let base = URL(fileURLWithPath: workspace.path, isDirectory: true)
            .deletingLastPathComponent()
        var projects: [BuildContainer] = []

        for match in regularExpression.matches(in: contents, range: range) {
            guard let pathRange = Range(match.range(at: 1), in: contents) else {
                continue
            }
            let encodedPath = String(contents[pathRange])
            let path = encodedPath.removingPercentEncoding ?? encodedPath
            let projectURL = base.appendingPathComponent(path).standardizedFileURL
            guard projectURL.path == root.path || projectURL.path.hasPrefix(rootPrefix) else {
                throw XcodeMetadataOperationError(
                    "A project referenced by the selected workspace is outside the active workspace."
                )
            }
            projects.append(BuildContainer(
                kind: .project,
                path: projectURL.path,
                label: projectURL.path.replacingOccurrences(of: rootPrefix, with: "")
            ))
        }

        return projects
    }

    private func containerArguments(_ container: BuildContainer) -> [String] {
        switch container.kind {
        case .workspace:
            return ["-workspace", container.path]
        case .project:
            return ["-project", container.path]
        }
    }

    private func diagnosticSuffix(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let tail = lines.suffix(20).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? "" : "\nFinal output:\n\(tail)"
    }

    private static func decodeList(_ output: String) throws -> ListEnvelope {
        guard let data = output.data(using: .utf8) else {
            throw XcodeMetadataOperationError("Xcode returned unrecognized list metadata.")
        }
        do {
            return try JSONDecoder().decode(ListEnvelope.self, from: data)
        } catch {
            throw XcodeMetadataOperationError("Xcode returned unrecognized list metadata.")
        }
    }

    private static func destinationFields(_ line: String) -> [String: String] {
        let body = line.dropFirst().dropLast()
        var fields: [String: String] = [:]
        for component in body.split(separator: ",", omittingEmptySubsequences: true) {
            let pair = component.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                continue
            }
            fields[String(pair[0]).trimmingCharacters(in: .whitespaces)] =
                String(pair[1]).trimmingCharacters(in: .whitespaces)
        }
        return fields
    }
}

private struct ListEnvelope: Decodable {
    let project: ListDetails?
    let workspace: ListDetails?
}

private struct ListDetails: Decodable {
    let configurations: [String]?
    let schemes: [String]?
}

public struct XcodeMetadataOperationError: HelperDomainFailure, Sendable {
    public let message: String
    public let processResult: ProcessResult?

    public var errorDescription: String? {
        message
    }

    public init(_ message: String, processResult: ProcessResult? = nil) {
        self.message = message
        self.processResult = processResult
    }
}
