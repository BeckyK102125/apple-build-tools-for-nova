import Foundation

public enum ContainerKind: String, Codable, Sendable {
    case workspace
    case project
}

public struct BuildContainer: Codable, Equatable, Sendable {
    public let kind: ContainerKind
    public let path: String
    public let label: String

    public init(kind: ContainerKind, path: String, label: String) {
        self.kind = kind
        self.path = path
        self.label = label
    }
}

public struct Toolchain: Codable, Equatable, Sendable {
    public let version: String
    public let build: String
    public let developerDirectory: String
    public let label: String

    public init(version: String, build: String, developerDirectory: String, label: String) {
        self.version = version
        self.build = build
        self.developerDirectory = developerDirectory
        self.label = label
    }
}

public struct Destination: Codable, Equatable, Sendable {
    public let label: String
    public let specifier: String
    public let platform: String
    public let id: String?
    public let generic: Bool

    public init(label: String, specifier: String, platform: String, id: String?, generic: Bool) {
        self.label = label
        self.specifier = specifier
        self.platform = platform
        self.id = id
        self.generic = generic
    }
}

public struct BuildSelection: Codable, Equatable, Sendable {
    public let developerDirectory: String
    public let container: BuildContainer
    public let scheme: String
    public let configuration: String
    public let destination: Destination

    public init(
        developerDirectory: String,
        container: BuildContainer,
        scheme: String,
        configuration: String,
        destination: Destination
    ) {
        self.developerDirectory = developerDirectory
        self.container = container
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
    }
}

public struct SavedBuildSelection: Codable, Equatable, Sendable {
    public let developerDirectory: String?
    public let containerKind: ContainerKind?
    public let containerPath: String?
    public let scheme: String?
    public let configuration: String?
    public let destinationLabel: String?
    public let destinationSpecifier: String?

    public init(
        developerDirectory: String?,
        containerKind: ContainerKind?,
        containerPath: String?,
        scheme: String?,
        configuration: String?,
        destinationLabel: String?,
        destinationSpecifier: String?
    ) {
        self.developerDirectory = developerDirectory
        self.containerKind = containerKind
        self.containerPath = containerPath
        self.scheme = scheme
        self.configuration = configuration
        self.destinationLabel = destinationLabel
        self.destinationSpecifier = destinationSpecifier
    }
}

public struct ProcessSpecification: Codable, Equatable, Sendable {
    public let command: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: String

    public init(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String

    public init(status: Int32, standardOutput: String, standardError: String) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public struct ValidationResult: Codable, Equatable, Sendable {
    public let valid: Bool
    public let errors: [String]

    public init(valid: Bool, errors: [String]) {
        self.valid = valid
        self.errors = errors
    }
}

public enum ProjectNavigatorNodeKind: String, Codable, Sendable {
    case project
    case group
    case folder
    case file
}

public struct ProjectNavigatorNode: Codable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let kind: ProjectNavigatorNodeKind
    public let path: String?
    public let children: [ProjectNavigatorNode]

    public init(
        identifier: String,
        name: String,
        kind: ProjectNavigatorNodeKind,
        path: String?,
        children: [ProjectNavigatorNode]
    ) {
        self.identifier = identifier
        self.name = name
        self.kind = kind
        self.path = path
        self.children = children
    }
}

public struct HelperResponse<Value: Codable>: Codable {
    public let ok: Bool
    public let value: Value?
    public let errors: [String]

    public init(ok: Bool, value: Value?, errors: [String]) {
        self.ok = ok
        self.value = value
        self.errors = errors
    }
}
