import Foundation

public protocol BuildCommandPreparing: Sendable {
    func makeSpecification(
        action: XcodeAction,
        selection: BuildSelection,
        workspaceRoot: String
    ) throws -> ProcessSpecification
}

public extension BuildCommandPreparing {
    func makeSpecification(
        selection: BuildSelection,
        workspaceRoot: String
    ) throws -> ProcessSpecification {
        try makeSpecification(
            action: .build,
            selection: selection,
            workspaceRoot: workspaceRoot
        )
    }
}

public enum XcodeAction: String, Codable, CaseIterable, Sendable {
    case build
    case clean
    case test
}

public struct BuildCommandBuilder: BuildCommandPreparing {
    private let forbiddenArguments: Set<String> = [
        "-allowprovisioningupdates",
        "-allowprovisioningdeviceregistration"
    ]

    public init() {}

    public func makeSpecification(
        action: XcodeAction,
        selection: BuildSelection,
        workspaceRoot: String
    ) throws -> ProcessSpecification {
        guard (workspaceRoot as NSString).isAbsolutePath else {
            throw BuildCommandError("The active workspace path must be absolute.")
        }
        guard (selection.developerDirectory as NSString).isAbsolutePath else {
            throw BuildCommandError("The selected Xcode developer directory must be absolute.")
        }

        let standardizedRoot = URL(
            fileURLWithPath: workspaceRoot,
            isDirectory: true
        ).standardizedFileURL.path
        let rootPrefix = standardizedRoot.hasSuffix("/")
            ? standardizedRoot
            : standardizedRoot + "/"
        let standardizedContainer = URL(
            fileURLWithPath: selection.container.path,
            isDirectory: true
        ).standardizedFileURL.path
        guard standardizedContainer == standardizedRoot
                || standardizedContainer.hasPrefix(rootPrefix) else {
            throw BuildCommandError(
                "The selected project or workspace is outside the active workspace."
            )
        }

        let containerArguments: [String]
        switch selection.container.kind {
        case .workspace:
            containerArguments = ["-workspace", standardizedContainer]
        case .project:
            containerArguments = ["-project", standardizedContainer]
        }

        let arguments = ["xcodebuild"]
            + containerArguments
            + [
                "-scheme", selection.scheme,
                "-configuration", selection.configuration,
                "-destination", selection.destination.specifier,
                action.rawValue
            ]
        guard !arguments.contains(where: { forbiddenArguments.contains($0.lowercased()) }) else {
            throw BuildCommandError("The build selection contains a forbidden argument.")
        }

        return ProcessSpecification(
            command: "/usr/bin/xcrun",
            arguments: arguments,
            environment: ["DEVELOPER_DIR": selection.developerDirectory],
            workingDirectory: standardizedRoot
        )
    }
}

private struct BuildCommandError: HelperDomainFailure {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
