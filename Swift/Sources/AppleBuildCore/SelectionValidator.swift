import Foundation

public struct AvailableBuildChoices: Equatable, Sendable {
    public let toolchains: [Toolchain]
    public let containers: [BuildContainer]
    public let schemes: [String]
    public let configurations: [String]
    public let destinations: [Destination]

    public init(
        toolchains: [Toolchain],
        containers: [BuildContainer],
        schemes: [String],
        configurations: [String],
        destinations: [Destination]
    ) {
        self.toolchains = toolchains
        self.containers = containers
        self.schemes = schemes
        self.configurations = configurations
        self.destinations = destinations
    }
}

public protocol SelectionValidating: Sendable {
    func validate(
        _ selection: BuildSelection,
        against current: AvailableBuildChoices
    ) -> ValidationResult
}

public struct SelectionValidator: SelectionValidating {
    public init() {}

    public func validate(
        _ selection: BuildSelection,
        against current: AvailableBuildChoices
    ) -> ValidationResult {
        var errors: [String] = []

        if !current.toolchains.contains(where: {
            standardizedPath($0.developerDirectory) == standardizedPath(selection.developerDirectory)
        }) {
            errors.append("The saved Xcode is no longer available. Select Xcode again.")
        }

        if !current.containers.contains(where: {
            $0.kind == selection.container.kind
                && standardizedPath($0.path) == standardizedPath(selection.container.path)
        }) {
            errors.append(
                "The saved project or workspace is no longer available. Select Project or Workspace again."
            )
        }

        if !current.schemes.contains(selection.scheme) {
            errors.append("The saved scheme is no longer available. Select Scheme again.")
        }

        if !current.configurations.contains(selection.configuration) {
            errors.append("The saved configuration is no longer available. Select Configuration again.")
        }

        if !current.destinations.contains(where: {
            $0.specifier == selection.destination.specifier
        }) {
            errors.append("The saved destination is no longer available. Select Destination again.")
        }

        return ValidationResult(valid: errors.isEmpty, errors: errors)
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
