import Foundation

public enum ReaderBlock: Equatable, Sendable {
    case heading(id: Int, level: Int, text: String)
    case paragraph(String)
    case code(String)
}

public enum MarkdownOutline {
    public static func parse(_ text: String) -> [ReaderBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [ReaderBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: String?
        var headingID = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let open = fence {
                if closes(line, open) {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code = []
                    fence = nil
                } else {
                    code.append(line)
                }
                continue
            }
            if let marker = fenceMarker(line) {
                flushParagraph()
                fence = marker
                continue
            }
            if let (level, title) = heading(line) {
                flushParagraph()
                headingID += 1
                blocks.append(.heading(id: headingID, level: level, text: title))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                continue
            }
            paragraph.append(line)
        }
        if fence != nil {
            // An unclosed fence keeps its content as code rather than losing it.
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    static func fenceMarker(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        guard line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" else {
            return nil
        }
        let run = trimmed.prefix(while: { $0 == first })
        return run.count >= 3 ? String(run) : nil
    }

    static func closes(_ line: String, _ open: String) -> Bool {
        guard let marker = fenceMarker(line), marker.first == open.first, marker.count >= open.count else {
            return false
        }
        let rest = line.drop(while: { $0 == " " }).dropFirst(marker.count)
        return rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (hashes.count, title)
    }
}
