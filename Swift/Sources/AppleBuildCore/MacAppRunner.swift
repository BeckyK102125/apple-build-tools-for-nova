import AppKit
import Foundation

/// Opens a built Mac app through LaunchServices (one copy, brought to the front) and streams what it
/// prints. Starting the app's program directly would keep it in the background, and `open -a` on such
/// a copy starts a second one, so the app's output goes to a log file that is read as it grows.
public struct MacAppRunner: Sendable {
    public init() {}

    public func run(appPath: String, write: @escaping @Sendable (Data) -> Void) async -> Int32 {
        let appURL = URL(fileURLWithPath: appPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            write(Data("The built app was not found: \(appURL.lastPathComponent)\n".utf8))
            return 1
        }
        await closeRunningCopies(of: appURL)

        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleBuildMacRun-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil),
              let reader = try? FileHandle(forReadingFrom: log) else {
            return 1
        }
        defer {
            try? reader.close()
            try? FileManager.default.removeItem(at: log)
        }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-W", "-n", "-a", appURL.path, "--stdout", log.path, "--stderr", log.path]
        do {
            try open.run()
        } catch {
            write(Data("The Mac app could not be opened.\n".utf8))
            return 1
        }

        var tailer = LogTailer()
        func forward(_ lines: [String]) {
            for line in lines { write(Data((line + "\n").utf8)) }
        }
        while open.isRunning {
            forward(tailer.append(reader.availableData))
            try? await Task.sleep(for: .milliseconds(200))
        }
        forward(tailer.append(reader.readDataToEndOfFile()))
        forward(tailer.finish())
        return open.terminationStatus
    }

    /// A previous run's copy of this exact app is closed first, so only one copy is ever open.
    private func closeRunningCopies(of appURL: URL) async {
        guard let identifier = Bundle(url: appURL)?.bundleIdentifier else { return }
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.bundleURL?.standardizedFileURL == appURL }
        guard !copies.isEmpty else { return }
        copies.forEach { $0.terminate() }
        for _ in 0..<15 where copies.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(200))
        }
        copies.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}
