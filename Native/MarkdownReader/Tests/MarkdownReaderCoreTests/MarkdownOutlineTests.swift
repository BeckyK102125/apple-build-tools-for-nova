import XCTest
@testable import MarkdownReaderCore

final class MarkdownOutlineTests: XCTestCase {
    func testHeadingsParagraphsAndIds() {
        XCTAssertEqual(MarkdownOutline.parse("# Title\n\nFirst line\nsecond line\n\n## Part\nBody\n###### Six"), [
            .heading(id: 1, level: 1, text: "Title"),
            .paragraph("First line\nsecond line"),
            .heading(id: 2, level: 2, text: "Part"),
            .paragraph("Body"),
            .heading(id: 3, level: 6, text: "Six")
        ])
    }

    func testThingsThatAreNotHeadings() {
        XCTAssertEqual(MarkdownOutline.parse("#NoSpace\n####### Seven\n#\n#   "), [
            .paragraph("#NoSpace\n####### Seven\n#\n#   ")
        ])
    }

    func testHashLinesInsideFencesStayCode() {
        let text = "## Before\n```swift\n# not a heading\n```\n~~~~\n# also code\n~~~\nstill code\n~~~~\n## After"
        XCTAssertEqual(MarkdownOutline.parse(text), [
            .heading(id: 1, level: 2, text: "Before"),
            .code("# not a heading"),
            .code("# also code\n~~~\nstill code"),
            .heading(id: 2, level: 2, text: "After")
        ])
    }

    func testBacktickFenceIsNotClosedByTildesOrShorterRuns() {
        XCTAssertEqual(MarkdownOutline.parse("````\n```\n~~~\n# code\n````"), [
            .code("```\n~~~\n# code")
        ])
    }

    func testWindowsLineEndingsAndUnclosedFence() {
        XCTAssertEqual(MarkdownOutline.parse("# Title\r\nText\r\n```\r\n# kept\r\nend"), [
            .heading(id: 1, level: 1, text: "Title"),
            .paragraph("Text"),
            .code("# kept\nend")
        ])
    }

    func testEmptyInput() {
        XCTAssertEqual(MarkdownOutline.parse(""), [])
        XCTAssertEqual(MarkdownOutline.parse("\n\n  \n"), [])
    }
}
