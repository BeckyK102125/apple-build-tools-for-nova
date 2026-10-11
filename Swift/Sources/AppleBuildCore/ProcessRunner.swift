import Foundation

public protocol ProcessRunning: Sendable {
    func run(_ specification: ProcessSpecification) async throws -> ProcessResult
}

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: specification.command)
        process.arguments = specification.arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in specification.environment {
            environment[key] = value
        }
        process.environment = environment
        process.currentDirectoryURL = URL(
            fileURLWithPath: specification.workingDirectory,
            isDirectory: true
        )
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()

        async let outputData = Task.detached {
            standardOutput.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let errorData = Task.detached {
            standardError.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let status = Task.detached {
            process.waitUntilExit()
            return process.terminationStatus
        }.value

        return await ProcessResult(
            status: status,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}
