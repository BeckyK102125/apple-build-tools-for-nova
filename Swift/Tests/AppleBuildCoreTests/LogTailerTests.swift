import XCTest
@testable import AppleBuildCore

final class LogTailerTests: XCTestCase {
    func testEmitsOnlyCompleteLinesAndKeepsThePartialOne() {
        var tailer = LogTailer()
        XCTAssertEqual(tailer.append(Data("first\nsec".utf8)), ["first"])
        XCTAssertEqual(tailer.append(Data("ond\nthird\n".utf8)), ["second", "third"])
        XCTAssertEqual(tailer.finish(), [])
    }

    func testFinishFlushesALastLineWithoutANewline() {
        var tailer = LogTailer()
        XCTAssertEqual(tailer.append(Data("done".utf8)), [])
        XCTAssertEqual(tailer.finish(), ["done"])
    }

    func testMultiByteCharactersSplitAcrossReadsStayWhole() {
        var tailer = LogTailer()
        let bytes = Array("café ☕️\n".utf8)
        XCTAssertEqual(tailer.append(Data(bytes[0..<4])), [])
        XCTAssertEqual(tailer.append(Data(bytes[4...])), ["café ☕️"])
    }

    func testWindowsLineEndingsAreTrimmed() {
        var tailer = LogTailer()
        XCTAssertEqual(tailer.append(Data("a\r\nb\r\n".utf8)), ["a", "b"])
    }
}
