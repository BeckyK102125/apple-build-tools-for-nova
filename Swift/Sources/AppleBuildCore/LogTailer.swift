import Foundation

/// Turns bytes appended to a growing log file into complete lines, keeping a partial last line
/// (and any split UTF-8 character) until the rest arrives.
public struct LogTailer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            lines.append(Self.text(pending[pending.startIndex..<newline]))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    public mutating func finish() -> [String] {
        defer { pending.removeAll() }
        return pending.isEmpty ? [] : [Self.text(pending)]
    }

    private static func text(_ bytes: Data) -> String {
        var line = String(decoding: bytes, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }
}
