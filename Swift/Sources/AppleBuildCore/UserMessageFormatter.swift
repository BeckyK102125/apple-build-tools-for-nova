import Foundation

public protocol UserMessageFormatting: Sendable {
    func currentSelection(toolchain: Toolchain?, saved: SavedBuildSelection) -> String
    func preflightErrors(_ errors: [String]) -> String
}

public struct UserMessageFormatter: UserMessageFormatting {
    public init() {}

    public func currentSelection(toolchain: Toolchain?, saved: SavedBuildSelection) -> String {
        let xcode: String
        if let toolchain {
            xcode = "Xcode \(toolchain.version), build \(toolchain.build), \(toolchain.developerDirectory)"
        } else {
            xcode = "Not selected"
        }

        let container: String
        if let kind = saved.containerKind, let path = saved.containerPath {
            let kindName = kind == .workspace ? "Workspace" : "Project"
            container = "\(kindName), \(path)"
        } else {
            container = "Not selected"
        }

        return [
            "Xcode: \(xcode)",
            "Project or Workspace: \(container)",
            "Scheme: \(saved.scheme ?? "Not selected")",
            "Configuration: \(saved.configuration ?? "Not selected")",
            "Destination: \(saved.destinationLabel ?? "Not selected")"
        ].joined(separator: "\n")
    }

    public func preflightErrors(_ errors: [String]) -> String {
        let numbered = errors.enumerated().map { index, error in
            "\(index + 1). \(error)"
        }
        return (["Preflight failed."] + numbered).joined(separator: "\n")
    }
}
