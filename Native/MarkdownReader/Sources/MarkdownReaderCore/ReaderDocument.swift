import Foundation

public struct ReaderHeading: Identifiable, Equatable, Sendable {
    public let id: Int
    public let level: Int
    public let text: String

    public init(id: Int, level: Int, text: String) {
        self.id = id; self.level = level; self.text = text
    }
}

public struct ReaderDocument: Equatable, Sendable {
    public static let maxBytes = 5 * 1024 * 1024
    static let shortenedNote = "This document was shortened to 5 MB."

    public let title: String
    public let source: String
    public let blocks: [ReaderBlock]
    /// Blocks as shown: long code split into 100-line pieces so a 10,000-line console lays out quickly.
    public let displayBlocks: [ReaderBlock]
    static let codeChunkLines = 100
    public let headings: [ReaderHeading]

    public init(source: String, fileName: String) {
        self.source = source
        let parsed = MarkdownOutline.parse(source)
        blocks = parsed.isEmpty ? [.paragraph("This document is empty.")] : parsed
        displayBlocks = blocks.flatMap(Self.chunked)
        headings = blocks.compactMap { block in
            if case let .heading(id, level, text) = block { return ReaderHeading(id: id, level: level, text: text) }
            return nil
        }
        title = headings.first(where: { $0.level == 1 })?.text ?? fileName
    }

    static func chunked(_ block: ReaderBlock) -> [ReaderBlock] {
        guard case let .code(text) = block else { return [block] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > codeChunkLines else { return [block] }
        return stride(from: 0, to: lines.count, by: codeChunkLines).map { start in
            .code(lines[start..<min(start + codeChunkLines, lines.count)].joined(separator: "\n"))
        }
    }

    public static func load(from url: URL, maxBytes: Int = ReaderDocument.maxBytes) -> ReaderDocument {
        guard let data = try? Data(contentsOf: url) else {
            let message = "This document could not be opened."
            return ReaderDocument(
                source: "# \(message)\n\nThe file could not be read. It may have been moved or deleted.",
                fileName: url.lastPathComponent
            )
        }
        if data.count > maxBytes {
            let text = String(decoding: data.prefix(maxBytes), as: UTF8.self)
            return ReaderDocument(source: text + "\n\n" + shortenedNote, fileName: url.lastPathComponent)
        }
        return ReaderDocument(source: String(decoding: data, as: UTF8.self), fileName: url.lastPathComponent)
    }
}
