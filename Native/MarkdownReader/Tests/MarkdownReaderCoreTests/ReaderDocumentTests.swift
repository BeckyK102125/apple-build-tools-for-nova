import XCTest
@testable import MarkdownReaderCore

final class ReaderDocumentTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderDocumentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    func testTitleHeadingsAndCopyText() {
        let document = ReaderDocument(source: "Intro\n# App Console\n## Summary", fileName: "console.md")
        XCTAssertEqual(document.title, "App Console")
        XCTAssertEqual(document.headings, [
            ReaderHeading(id: 1, level: 1, text: "App Console"),
            ReaderHeading(id: 2, level: 2, text: "Summary")
        ])
        XCTAssertEqual(document.source, "Intro\n# App Console\n## Summary")
    }

    func testTitleFallsBackToFileName() {
        XCTAssertEqual(ReaderDocument(source: "## Only level two", fileName: "report.md").title, "report.md")
    }

    func testEmptyDocumentSaysSo() {
        let document = ReaderDocument(source: "  \n", fileName: "empty.md")
        XCTAssertEqual(document.blocks, [.paragraph("This document is empty.")])
    }

    func testUnreadableFileExplainsInPlainWords() {
        let document = ReaderDocument.load(from: folder.appendingPathComponent("missing.md"))
        XCTAssertEqual(document.title, "This document could not be opened.")
        XCTAssertEqual(document.blocks.first, .heading(id: 1, level: 1, text: "This document could not be opened."))
    }

    func testLargeFileIsShortenedWithANote() throws {
        let url = folder.appendingPathComponent("big.md")
        try Data(("# Big\n" + String(repeating: "x", count: 100)).utf8).write(to: url)
        let document = ReaderDocument.load(from: url, maxBytes: 20)
        XCTAssertTrue(document.source.hasSuffix("\n\nThis document was shortened to 5 MB."))
        XCTAssertEqual(document.title, "Big")
    }

    func testLongCodeBlocksAreSplitIntoChunksForFastLayout() {
        let lines = (1...250).map { "line \($0)" }
        let document = ReaderDocument(source: "# Log\n```\n" + lines.joined(separator: "\n") + "\n```", fileName: "log.md")

        XCTAssertEqual(document.displayBlocks.count, 4)
        XCTAssertEqual(document.displayBlocks[0], .heading(id: 1, level: 1, text: "Log"))
        XCTAssertEqual(document.displayBlocks[1], .code(lines[0..<100].joined(separator: "\n")))
        XCTAssertEqual(document.displayBlocks[3], .code(lines[200..<250].joined(separator: "\n")))
        XCTAssertEqual(document.blocks.count, 2)
    }

    @MainActor
    func testOpeningASecondDocumentReplacesTheFirst() throws {
        let first = folder.appendingPathComponent("first.md")
        let second = folder.appendingPathComponent("second.md")
        try Data("# First".utf8).write(to: first)
        try Data("# Second".utf8).write(to: second)
        let model = ReaderModel()

        model.open(first)
        model.open(second)

        XCTAssertEqual(model.document?.title, "Second")
        XCTAssertEqual(model.revision, 2)
    }
}
