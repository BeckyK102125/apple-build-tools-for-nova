import Foundation

public struct LogFileStoreError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?
}

public struct LogFileStore: Sendable {
    public static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Apple Build Tools for Nova", isDirectory: true)

    private let root: URL
    private let keep: Int
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(root: URL = LogFileStore.defaultRoot, keep: Int = 20,
                now: @escaping @Sendable () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.root = root; self.keep = keep; self.now = now; self.timeZone = timeZone
    }

    public func write(appName: String, title: String, contents: String) throws -> String {
        let folder = root.appendingPathComponent(Self.sanitize(appName), isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let stamp = formatter.string(from: now())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent("\(stamp) \(Self.sanitize(title)).md")
            var suffix = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(stamp) \(Self.sanitize(title)) \(suffix).md")
                suffix += 1
            }
            try Data(contents.utf8).write(to: url, options: .atomic)
            try prune(folder)
            return url.path
        } catch {
            throw LogFileStoreError(errorDescription: "The log folder could not be written.")
        }
    }

    private func prune(_ folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".md") }.sorted()
        for name in names.dropLast(keep) {
            try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? "App" : String(cleaned.prefix(100))
    }
}
