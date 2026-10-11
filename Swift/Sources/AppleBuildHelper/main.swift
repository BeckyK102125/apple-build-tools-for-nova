import AppleBuildCore
import Dispatch
import Foundation

let application = HelperApplication(
    locator: WorkspaceLocator(),
    toolchainResolver: ToolchainResolver(),
    metadataService: XcodeMetadataService(),
    selectionValidator: SelectionValidator(),
    buildCommandBuilder: BuildCommandBuilder(),
    signingStatusService: SigningStatusService(),
    deviceRunService: DeviceRunService(),
    diagnosticsService: AppDiagnosticsService(),
    messageFormatter: UserMessageFormatter(),
    navigator: ProjectNavigatorService(),
    writeStandardOutput: { FileHandle.standardOutput.write($0) },
    writeStandardError: { FileHandle.standardError.write($0) }
)

Task {
    let status = await application.run(arguments: Array(CommandLine.arguments.dropFirst()))
    exit(status)
}

dispatchMain()
