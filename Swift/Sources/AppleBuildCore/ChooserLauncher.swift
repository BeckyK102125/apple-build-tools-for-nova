import Foundation

public struct ChooserLaunchError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public protocol ChooserLaunching: Sendable {
    /// Returns the chosen index, or nil when the tester cancels.
    func choose(readerPath: String, request: Data) async throws -> Int?
}

/// Opens the reader's accessible chooser through LaunchServices so it comes to the front,
/// waits for the answer, and returns it. Starting the reader directly does not bring it forward.
public struct ChooserLauncher: ChooserLaunching, Sendable {
    private let processRunner: any ProcessRunning

    public init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    public func choose(readerPath: String, request: Data) async throws -> Int? {
        let failure = ChooserLaunchError("The accessible chooser could not open.")
        guard let parsed = try? JSONDecoder().decode(Request.self, from: request),
              !parsed.title.isEmpty, !parsed.items.isEmpty, parsed.items.count <= 500 else {
            throw failure
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleBuildChooser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("request.json")
        let output = folder.appendingPathComponent("answer.json")
        try request.write(to: input)

        let result = try await processRunner.run(ProcessSpecification(
            command: "/usr/bin/open",
            arguments: ["-W", "-n", "-a", readerPath, "--stdin", input.path, "--stdout", output.path,
                        "--args", "--choose"],
            environment: [:],
            workingDirectory: folder.path
        ))
        guard result.status == 0,
              let data = try? Data(contentsOf: output),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
            throw failure
        }
        if let index = answer.index {
            guard parsed.items.indices.contains(index) else { throw failure }
            return index
        }
        return nil
    }

    private struct Request: Decodable {
        let title: String
        let items: [String]
    }

    private struct Answer: Decodable {
        let index: Int?
    }
}
