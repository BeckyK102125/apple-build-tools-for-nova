import Foundation

func projectNavigatorNamePrecedes(_ lhs: String, _ rhs: String) -> Bool {
    let locale = Locale(identifier: "en_US_POSIX")
    let lhsFolded = lhs.lowercased(with: locale)
    let rhsFolded = rhs.lowercased(with: locale)
    if lhsFolded != rhsFolded {
        return lhsFolded < rhsFolded
    }
    return lhs < rhs
}

public protocol ProjectNavigatorProviding: Sendable {
    func projectTree(
        workspaceRoot: String,
        containerKind: ContainerKind,
        containerPath: String
    ) throws -> ProjectNavigatorNode
}

public struct ProjectNavigatorService: ProjectNavigatorProviding {
    public init() {}

    public func projectTree(
        workspaceRoot: String,
        containerKind: ContainerKind,
        containerPath: String
    ) throws -> ProjectNavigatorNode {
        guard containerKind == .project else {
            throw ProjectNavigatorError(
                "Project Navigator currently supports selected Xcode projects, not workspaces. "
                    + "Select Project or Workspace and choose a project."
            )
        }

        let rootURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true).standardizedFileURL
        let projectURL = URL(fileURLWithPath: containerPath, isDirectory: true).standardizedFileURL
        guard projectURL.pathExtension == "xcodeproj", isInside(projectURL, root: rootURL) else {
            throw ProjectNavigatorError("The selected Xcode project is outside the current Nova workspace.")
        }

        let projectFile = projectURL.appendingPathComponent("project.pbxproj", isDirectory: false)
        guard isInside(projectFile, root: rootURL) else {
            throw ProjectNavigatorError("The selected Xcode project file is outside the current Nova workspace.")
        }
        let data: Data
        do {
            data = try Data(contentsOf: projectFile)
        } catch {
            throw ProjectNavigatorError("The selected Xcode project could not be read.")
        }

        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw ProjectNavigatorError("The selected Xcode project file is not a valid property list.")
        }
        guard
            let document = plist as? [String: Any],
            let objects = document["objects"] as? [String: Any],
            let rootObjectIdentifier = document["rootObject"] as? String,
            let projectObject = objects[rootObjectIdentifier] as? [String: Any],
            let mainGroupIdentifier = projectObject["mainGroup"] as? String,
            let mainGroup = objects[mainGroupIdentifier] as? [String: Any]
        else {
            throw ProjectNavigatorError("The selected Xcode project is missing its main group.")
        }

        let projectDirectory = projectURL.deletingLastPathComponent()
        let productGroupIdentifier = projectObject["productRefGroup"] as? String
        let context = ParseContext(
            objects: objects,
            workspaceRoot: rootURL,
            projectDirectory: projectDirectory,
            productGroupIdentifier: productGroupIdentifier,
            fileManager: .default
        )
        guard let mainBase = context.groupBase(for: mainGroup, parentBase: projectDirectory) else {
            throw ProjectNavigatorError("The selected Xcode project main group uses an unsupported source tree.")
        }
        let children = context.children(
            of: mainGroup,
            parentBase: mainBase,
            visitedGroups: [mainGroupIdentifier]
        )
        let projectName = projectURL.deletingPathExtension().lastPathComponent

        return ProjectNavigatorNode(
            identifier: "project:\(projectURL.path)",
            name: projectName,
            kind: .project,
            path: projectURL.path,
            children: children
        )
    }

    private func isInside(_ candidate: URL, root: URL) -> Bool {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return candidatePath == resolvedRoot || candidatePath.hasPrefix(rootPath)
    }
}

private struct ParseContext {
    let objects: [String: Any]
    let workspaceRoot: URL
    let projectDirectory: URL
    let productGroupIdentifier: String?
    let fileManager: FileManager

    func children(
        of group: [String: Any],
        parentBase: URL,
        visitedGroups: Set<String>
    ) -> [ProjectNavigatorNode] {
        guard let childIdentifiers = group["children"] as? [String] else {
            return []
        }
        return childIdentifiers.compactMap { identifier in
            guard identifier != productGroupIdentifier else {
                return nil
            }
            return node(
                identifier: identifier,
                parentBase: parentBase,
                visitedGroups: visitedGroups
            )
        }
    }

    func node(
        identifier: String,
        parentBase: URL,
        visitedGroups: Set<String>
    ) -> ProjectNavigatorNode? {
        guard let object = objects[identifier] as? [String: Any], let isa = object["isa"] as? String else {
            return nil
        }
        guard identifier != productGroupIdentifier else {
            return nil
        }

        switch isa {
        case "PBXGroup", "PBXVariantGroup", "XCVersionGroup":
            guard !visitedGroups.contains(identifier) else {
                return nil
            }
            guard let base = groupBase(for: object, parentBase: parentBase) else {
                return nil
            }
            let childNodes = children(
                of: object,
                parentBase: base,
                visitedGroups: visitedGroups.union([identifier])
            )
            guard !childNodes.isEmpty else {
                return nil
            }
            return ProjectNavigatorNode(
                identifier: "pbx:\(identifier)",
                name: displayName(for: object, fallback: identifier),
                kind: .group,
                path: isInside(base) ? base.path : nil,
                children: childNodes
            )

        case "PBXFileSystemSynchronizedRootGroup":
            guard let base = groupBase(for: object, parentBase: parentBase) else {
                return nil
            }
            guard isInside(base) else {
                return nil
            }
            return ProjectNavigatorNode(
                identifier: "pbx:\(identifier)",
                name: displayName(for: object, fallback: identifier),
                kind: .group,
                path: base.path,
                children: filesystemChildren(at: base, visitedDirectories: [])
            )

        case "PBXFileReference":
            guard let path = resolvedFilePath(for: object, parentBase: parentBase), isInside(path) else {
                return nil
            }
            return ProjectNavigatorNode(
                identifier: "pbx:\(identifier)",
                name: displayName(for: object, fallback: path.lastPathComponent),
                kind: .file,
                path: path.path,
                children: []
            )

        default:
            return nil
        }
    }

    func groupBase(for object: [String: Any], parentBase: URL) -> URL? {
        let sourceTree = object["sourceTree"] as? String ?? "<group>"
        let base: URL
        switch sourceTree {
        case "<group>":
            base = parentBase
        case "SOURCE_ROOT", "PROJECT_DIR":
            base = projectDirectory
        case "<absolute>":
            base = URL(fileURLWithPath: "/", isDirectory: true)
        default:
            return nil
        }
        guard let path = object["path"] as? String, !path.isEmpty else {
            return base.standardizedFileURL
        }
        guard !containsExcludedComponent(path) else {
            return nil
        }
        return base.appendingPathComponent(path, isDirectory: true).standardizedFileURL
    }

    private func resolvedFilePath(for object: [String: Any], parentBase: URL) -> URL? {
        guard let path = object["path"] as? String, !path.isEmpty else {
            return nil
        }
        guard !containsExcludedComponent(path, allowsGeneratedLeaf: true) else {
            return nil
        }
        let sourceTree = object["sourceTree"] as? String ?? "<group>"
        switch sourceTree {
        case "<group>":
            return parentBase.appendingPathComponent(path).standardizedFileURL
        case "SOURCE_ROOT", "PROJECT_DIR":
            return projectDirectory.appendingPathComponent(path).standardizedFileURL
        case "<absolute>":
            return URL(fileURLWithPath: path).standardizedFileURL
        default:
            return nil
        }
    }

    private func filesystemChildren(
        at directory: URL,
        visitedDirectories: Set<String>
    ) -> [ProjectNavigatorNode] {
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        guard isInside(resolvedDirectory), !visitedDirectories.contains(resolvedDirectory.path) else {
            return []
        }
        let nextVisited = visitedDirectories.union([resolvedDirectory.path])
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let ignoredDirectories: Set<String> = [".build", ".swiftpm", "build", "deriveddata"]
        let entries: [(url: URL, isDirectory: Bool, isPackage: Bool)] = urls.compactMap { url in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard isInside(resolved) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDirectory = values?.isDirectory == true
            if isDirectory && ignoredDirectories.contains(url.lastPathComponent.lowercased()) {
                return nil
            }
            return (url, isDirectory, values?.isPackage == true)
        }
        .sorted { lhs, rhs in
            let lhsFolder = lhs.isDirectory && !lhs.isPackage
            let rhsFolder = rhs.isDirectory && !rhs.isPackage
            if lhsFolder != rhsFolder {
                return lhsFolder
            }
            return projectNavigatorNamePrecedes(
                lhs.url.lastPathComponent,
                rhs.url.lastPathComponent
            )
        }

        return entries.map { entry in
            let isFolder = entry.isDirectory && !entry.isPackage
            return ProjectNavigatorNode(
                identifier: "fs:\(entry.url.standardizedFileURL.path)",
                name: entry.url.lastPathComponent,
                kind: isFolder ? .folder : .file,
                path: entry.url.standardizedFileURL.path,
                children: isFolder
                    ? filesystemChildren(at: entry.url, visitedDirectories: nextVisited)
                    : []
            )
        }
    }

    private func displayName(for object: [String: Any], fallback: String) -> String {
        if let name = object["name"] as? String, !name.isEmpty {
            return name
        }
        if let path = object["path"] as? String, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return fallback
    }

    private func containsExcludedComponent(
        _ path: String,
        allowsGeneratedLeaf: Bool = false
    ) -> Bool {
        let generatedNames: Set<String> = [".build", ".swiftpm", "build", "deriveddata"]
        let components = NSString(string: path).pathComponents
        return components.enumerated().contains { index, component in
            let lowered = component.lowercased()
            let isHidden = component.hasPrefix(".") && component != "." && component != ".."
            let isGeneratedDirectory = generatedNames.contains(lowered)
                && !(allowsGeneratedLeaf && index == components.indices.last)
            return isHidden || isGeneratedDirectory
        }
    }

    private func isInside(_ url: URL) -> Bool {
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        let root = workspaceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate == root || candidate.hasPrefix(prefix)
    }
}

private struct ProjectNavigatorError: HelperDomainFailure {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
