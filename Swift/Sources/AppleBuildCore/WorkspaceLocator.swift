import Foundation

public protocol WorkspaceLocating: Sendable {
    func locate(in workspaceRoot: String) throws -> [BuildContainer]
}

public struct WorkspaceLocator: WorkspaceLocating {
    private let fileManager: SendableFileManager
    private let skippedDirectoryNames: Set<String>
    private let directoryContents: @Sendable (URL, [URLResourceKey]) throws -> [URL]

    public init(fileManager: FileManager = .default) {
        let sendableFileManager = SendableFileManager(fileManager)
        self.fileManager = sendableFileManager
        skippedDirectoryNames = [
            ".git", ".nova", ".build", "DerivedData", "Pods", "Carthage"
        ]
        directoryContents = { directory, keys in
            try sendableFileManager.value.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: []
            )
        }
    }

    init(
        fileManager: FileManager,
        directoryContents: @escaping @Sendable (URL, [URLResourceKey]) throws -> [URL]
    ) {
        self.fileManager = SendableFileManager(fileManager)
        skippedDirectoryNames = [
            ".git", ".nova", ".build", "DerivedData", "Pods", "Carthage"
        ]
        self.directoryContents = directoryContents
    }

    public func locate(in workspaceRoot: String) throws -> [BuildContainer] {
        let root = URL(fileURLWithPath: workspaceRoot, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.value.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceLocatorError.unavailable
        }

        if let rootKind = containerKind(for: root) {
            return [BuildContainer(kind: rootKind, path: root.path, label: root.lastPathComponent)]
        }

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let requestedKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        var pendingDirectories = [root]
        var nextIndex = 0
        var results: [BuildContainer] = []

        while nextIndex < pendingDirectories.count {
            let directory = pendingDirectories[nextIndex]
            nextIndex += 1

            let children: [URL]
            do {
                children = try directoryContents(directory, Array(requestedKeys))
            } catch {
                if directory == root {
                    throw WorkspaceLocatorError.unavailable
                }
                continue
            }

            for child in children {
                let standardizedChild = child.standardizedFileURL
                guard standardizedChild.path.hasPrefix(rootPrefix) else {
                    continue
                }

                guard let values = try? standardizedChild.resourceValues(forKeys: requestedKeys),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    continue
                }

                let kind = containerKind(for: standardizedChild)
                if kind == nil, shouldSkipTraversal(of: standardizedChild) {
                    continue
                }

                if let kind {
                    let label = String(standardizedChild.path.dropFirst(rootPrefix.count))
                    results.append(BuildContainer(kind: kind, path: standardizedChild.path, label: label))
                } else {
                    pendingDirectories.append(standardizedChild)
                }
            }
        }

        return results.sorted(by: sortContainers)
    }

    private func shouldSkipTraversal(of directory: URL) -> Bool {
        let name = directory.lastPathComponent
        if name.hasPrefix(".") || skippedDirectoryNames.contains(name) {
            return true
        }

        return name == "SourcePackages"
            && directory.deletingLastPathComponent().lastPathComponent == "build"
    }

    private func containerKind(for url: URL) -> ContainerKind? {
        switch url.pathExtension.lowercased() {
        case "xcworkspace":
            return .workspace
        case "xcodeproj":
            return .project
        default:
            return nil
        }
    }

    private func sortContainers(_ lhs: BuildContainer, _ rhs: BuildContainer) -> Bool {
        let lhsDepth = lhs.label.split(separator: "/").count
        let rhsDepth = rhs.label.split(separator: "/").count
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }

        if lhs.kind != rhs.kind {
            return lhs.kind == .workspace
        }

        let labelOrder = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
        if labelOrder != .orderedSame {
            return labelOrder == .orderedAscending
        }
        return lhs.path < rhs.path
    }
}

final class SendableFileManager: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

private enum WorkspaceLocatorError: HelperDomainFailure {
    case unavailable

    var errorDescription: String? {
        "Workspace folder is unavailable."
    }
}
