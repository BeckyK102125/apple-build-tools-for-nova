import Foundation

public struct HelperApplication: Sendable {
    private let locator: any WorkspaceLocating
    private let toolchainResolver: any ToolchainResolving
    private let metadataService: any XcodeMetadataProviding
    private let selectionValidator: any SelectionValidating
    private let buildCommandBuilder: any BuildCommandPreparing
    private let signingStatusService: any SigningStatusProviding
    private let deviceRunService: any DeviceRunPreparing
    private let diagnosticsService: any AppDiagnosticsProviding
    private let chooserLauncher: any ChooserLaunching
    private let logStore: LogFileStore
    private let readStandardInput: @Sendable () -> Data
    private let messageFormatter: any UserMessageFormatting
    private let navigator: any ProjectNavigatorProviding
    private let writeStandardOutput: @Sendable (Data) -> Void
    private let writeStandardError: @Sendable (Data) -> Void

    public init(
        locator: any WorkspaceLocating,
        toolchainResolver: any ToolchainResolving,
        metadataService: any XcodeMetadataProviding,
        selectionValidator: any SelectionValidating,
        buildCommandBuilder: any BuildCommandPreparing,
        signingStatusService: any SigningStatusProviding,
        deviceRunService: any DeviceRunPreparing = DeviceRunService(),
        diagnosticsService: any AppDiagnosticsProviding = AppDiagnosticsService(),
        chooserLauncher: any ChooserLaunching = ChooserLauncher(),
        logStore: LogFileStore = LogFileStore(),
        readStandardInput: @escaping @Sendable () -> Data = { FileHandle.standardInput.readDataToEndOfFile() },
        messageFormatter: any UserMessageFormatting,
        navigator: any ProjectNavigatorProviding,
        writeStandardOutput: @escaping @Sendable (Data) -> Void,
        writeStandardError: @escaping @Sendable (Data) -> Void
    ) {
        self.locator = locator
        self.toolchainResolver = toolchainResolver
        self.metadataService = metadataService
        self.selectionValidator = selectionValidator
        self.buildCommandBuilder = buildCommandBuilder
        self.signingStatusService = signingStatusService
        self.deviceRunService = deviceRunService
        self.diagnosticsService = diagnosticsService
        self.chooserLauncher = chooserLauncher
        self.logStore = logStore
        self.readStandardInput = readStandardInput
        self.messageFormatter = messageFormatter
        self.navigator = navigator
        self.writeStandardOutput = writeStandardOutput
        self.writeStandardError = writeStandardError
    }

    public func run(arguments: [String]) async -> Int32 {
        do {
            let command = try HelperCommand.parse(arguments: arguments)
            switch command {
            case let .toolchains(applications, savedDeveloperDirectory):
                let value = await toolchainResolver.discover(
                    applicationsDirectory: applications,
                    savedDeveloperDirectory: savedDeveloperDirectory
                )
                try writeSuccess(value)

            case let .containers(workspaceRoot):
                try writeSuccess(locator.locate(in: workspaceRoot))

            case let .schemes(workspaceRoot, developerDirectory, kind, path):
                _ = try await toolchainResolver.validate(developerDirectory)
                try writeSuccess(try await metadataService.schemes(
                    for: container(kind: kind, path: path),
                    workspaceRoot: workspaceRoot,
                    developerDirectory: developerDirectory
                ))

            case let .configurations(workspaceRoot, developerDirectory, kind, path):
                _ = try await toolchainResolver.validate(developerDirectory)
                try writeSuccess(try await metadataService.configurations(
                    for: container(kind: kind, path: path),
                    workspaceRoot: workspaceRoot,
                    developerDirectory: developerDirectory
                ))

            case let .destinations(workspaceRoot, developerDirectory, kind, path, scheme):
                _ = try await toolchainResolver.validate(developerDirectory)
                try writeSuccess(try await metadataService.destinations(
                    for: container(kind: kind, path: path),
                    scheme: scheme,
                    workspaceRoot: workspaceRoot,
                    developerDirectory: developerDirectory
                ))

            case let .prepareAction(action, workspaceRoot, selectionJSON):
                let selection = try await resolveSelection(
                    selectionJSON: selectionJSON,
                    workspaceRoot: workspaceRoot
                )
                try writeSuccess(try buildCommandBuilder.makeSpecification(
                    action: action,
                    selection: selection,
                    workspaceRoot: workspaceRoot
                ))

            case let .signingStatus(workspaceRoot, selectionJSON):
                let selection = try await resolveSelection(
                    selectionJSON: selectionJSON,
                    workspaceRoot: workspaceRoot
                )
                try writeSuccess(try await signingStatusService.inspect(
                    selection: selection,
                    workspaceRoot: workspaceRoot
                ))

            case let .prepareDeviceRun(workspaceRoot, selectionJSON):
                let selection = try await resolveSelection(
                    selectionJSON: selectionJSON,
                    workspaceRoot: workspaceRoot
                )
                try writeSuccess(try await deviceRunService.prepare(
                    selection: selection,
                    workspaceRoot: workspaceRoot
                ))

            case let .appReports(workspaceRoot, selectionJSON, sinceEpoch):
                let selection = try await resolveSelection(selectionJSON: selectionJSON, workspaceRoot: workspaceRoot)
                try writeSuccess(try await diagnosticsService.listReports(
                    selection: selection, workspaceRoot: workspaceRoot,
                    since: sinceEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ))

            case let .appReport(workspaceRoot, selectionJSON, source):
                let selection = try await resolveSelection(selectionJSON: selectionJSON, workspaceRoot: workspaceRoot)
                try writeSuccess(try await diagnosticsService.openReport(
                    selection: selection, workspaceRoot: workspaceRoot, source: source
                ))

            case let .writeConsole(workspaceRoot, selectionJSON):
                guard let capture = try? JSONDecoder().decode(ConsoleCapture.self, from: readStandardInput()) else {
                    throw HelperInputError("The App Console data was not readable.")
                }
                let selection = try await resolveSelection(selectionJSON: selectionJSON, workspaceRoot: workspaceRoot)
                try writeSuccess(try await diagnosticsService.writeConsole(
                    selection: selection, workspaceRoot: workspaceRoot, capture: capture
                ))

            case let .writeDocument(appName, title):
                // Saves a Markdown report (for example a build report) so the reader can open it.
                let data = readStandardInput()
                guard data.count <= 25_000_000 else {
                    throw HelperInputError("The report is too large to save.")
                }
                try writeSuccess(try logStore.write(appName: appName, title: title,
                                                    contents: String(decoding: data, as: UTF8.self)))

            case let .macRun(appPath):
                // Streams the app's output as plain lines (not JSON); this is a launch, not a query.
                return await MacAppRunner().run(appPath: appPath, write: writeStandardOutput)

            case let .choose(readerPath):
                let index = try await chooserLauncher.choose(readerPath: readerPath, request: readStandardInput())
                try writeSuccess(ChooserAnswer(index: index))

            case let .currentSelection(_, selectionJSON):
                let saved = try decodeSelection(selectionJSON)
                let toolchain: Toolchain?
                if let developerDirectory = saved.developerDirectory {
                    toolchain = try? await toolchainResolver.validate(developerDirectory)
                } else {
                    toolchain = nil
                }
                try writeSuccess(messageFormatter.currentSelection(
                    toolchain: toolchain,
                    saved: saved
                ))

            case let .projectNavigator(workspaceRoot, containerKind, containerPath):
                try writeSuccess(try navigator.projectTree(
                    workspaceRoot: workspaceRoot,
                    containerKind: containerKind,
                    containerPath: containerPath
                ))
            }
            return 0
        } catch let error as SelectionResolutionError {
            return writeDomainFailure(errors: error.errors)
        } catch let error as any HelperDomainFailure {
            return writeDomainFailure(errors: [error.localizedDescription])
        } catch {
            writeStandardError(Data(
                "AppleBuildHelper could not complete the request. \(error.localizedDescription)\n".utf8
            ))
            return 1
        }
    }

    private func resolve(
        saved: SavedBuildSelection,
        workspaceRoot: String
    ) async throws -> SelectionResolution {
        var errors: [String] = []
        let toolchain: Toolchain?
        if let developerDirectory = saved.developerDirectory {
            do {
                toolchain = try await toolchainResolver.validate(developerDirectory)
            } catch is any HelperDomainFailure {
                toolchain = nil
                errors.append("The saved Xcode is no longer available. Select Xcode again.")
            } catch {
                throw error
            }
        } else {
            toolchain = nil
            errors.append("Xcode is not selected. Select Xcode.")
        }

        let containers = try locator.locate(in: workspaceRoot)
        let selectedContainer: BuildContainer?
        if let kind = saved.containerKind, let path = saved.containerPath {
            selectedContainer = containers.first {
                $0.kind == kind && standardizedPath($0.path) == standardizedPath(path)
            }
            if selectedContainer == nil {
                errors.append(
                    "The saved project or workspace is no longer available. Select Project or Workspace again."
                )
            }
        } else {
            selectedContainer = nil
            errors.append("A project or workspace is not selected. Select Project or Workspace.")
        }

        var schemes: [String] = []
        var configurations: [String] = []
        var destinations: [Destination] = []
        if let toolchain, let selectedContainer {
            schemes = try await metadataService.schemes(
                for: selectedContainer,
                workspaceRoot: workspaceRoot,
                developerDirectory: toolchain.developerDirectory
            )
            configurations = try await metadataService.configurations(
                for: selectedContainer,
                workspaceRoot: workspaceRoot,
                developerDirectory: toolchain.developerDirectory
            )
            if let scheme = saved.scheme, schemes.contains(scheme) {
                destinations = try await metadataService.destinations(
                    for: selectedContainer,
                    scheme: scheme,
                    workspaceRoot: workspaceRoot,
                    developerDirectory: toolchain.developerDirectory
                )
            }
        }

        if saved.scheme == nil {
            errors.append("A scheme is not selected. Select Scheme.")
        } else if !schemes.contains(saved.scheme!) {
            errors.append("The saved scheme is no longer available. Select Scheme again.")
        }
        if saved.configuration == nil {
            errors.append("A configuration is not selected. Select Configuration.")
        } else if !configurations.contains(saved.configuration!) {
            errors.append("The saved configuration is no longer available. Select Configuration again.")
        }

        let selectedDestination: Destination?
        if let specifier = saved.destinationSpecifier {
            selectedDestination = destinations.first { $0.specifier == specifier }
            if selectedDestination == nil {
                errors.append("The saved destination is no longer available. Select Destination again.")
            }
        } else {
            selectedDestination = nil
            errors.append("A destination is not selected. Select Destination.")
        }

        let choices = AvailableBuildChoices(
            toolchains: toolchain.map { [$0] } ?? [],
            containers: containers,
            schemes: schemes,
            configurations: configurations,
            destinations: destinations
        )
        let selection: BuildSelection?
        if errors.isEmpty,
           let toolchain,
           let selectedContainer,
           let scheme = saved.scheme,
           let configuration = saved.configuration,
           let selectedDestination {
            selection = BuildSelection(
                developerDirectory: toolchain.developerDirectory,
                container: selectedContainer,
                scheme: scheme,
                configuration: configuration,
                destination: selectedDestination
            )
        } else {
            selection = nil
        }
        return SelectionResolution(selection: selection, choices: choices, errors: errors)
    }

    private func decodeSelection(_ json: String) throws -> SavedBuildSelection {
        guard let data = json.data(using: .utf8) else {
            throw HelperInputError("The saved build selection is invalid.")
        }
        do {
            return try JSONDecoder().decode(SavedBuildSelection.self, from: data)
        } catch {
            throw HelperInputError("The saved build selection is invalid.")
        }
    }

    private func resolveSelection(
        selectionJSON: String,
        workspaceRoot: String
    ) async throws -> BuildSelection {
        let saved = try decodeSelection(selectionJSON)
        let resolution = try await resolve(saved: saved, workspaceRoot: workspaceRoot)
        guard let selection = resolution.selection else {
            throw SelectionResolutionError(errors: resolution.errors)
        }
        let validation = selectionValidator.validate(
            selection,
            against: resolution.choices
        )
        guard validation.valid else {
            throw SelectionResolutionError(errors: validation.errors)
        }
        return selection
    }

    private func writeSuccess<Value: Codable>(_ value: Value) throws {
        var data = try JSONEmitter.encode(HelperResponse(ok: true, value: value, errors: []))
        data.append(contentsOf: "\n".utf8)
        writeStandardOutput(data)
    }

    private func writeDomainFailure(errors: [String]) -> Int32 {
        do {
            var data = try JSONEmitter.encode(HelperResponse<String>(
                ok: false,
                value: nil,
                errors: errors
            ))
            data.append(contentsOf: "\n".utf8)
            writeStandardOutput(data)
            return 2
        } catch {
            writeStandardError(Data("AppleBuildHelper could not encode its response.\n".utf8))
            return 1
        }
    }

    private func container(kind: ContainerKind, path: String) -> BuildContainer {
        BuildContainer(
            kind: kind,
            path: path,
            label: URL(fileURLWithPath: path).lastPathComponent
        )
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

/// Always writes "index" (null when cancelled) so the extension can tell cancel from failure.
private struct ChooserAnswer: Codable {
    let index: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
    }
}

private struct SelectionResolution {
    let selection: BuildSelection?
    let choices: AvailableBuildChoices
    let errors: [String]
}

private struct SelectionResolutionError: Error {
    let errors: [String]
}

private struct HelperInputError: HelperDomainFailure {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
