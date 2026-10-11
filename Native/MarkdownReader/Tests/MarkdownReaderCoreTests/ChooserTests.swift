import XCTest
@testable import MarkdownReaderCore

final class ChooserTests: XCTestCase {
    func testDecodesARequestWithTitleAndItems() throws {
        let request = try ChooserRequest.decode(Data(#"{"title":"Select a build destination","items":["My Mac","Sam’s iPhone"]}"#.utf8))
        XCTAssertEqual(request, ChooserRequest(title: "Select a build destination", items: ["My Mac", "Sam’s iPhone"]))
    }

    func testRejectsEmptyOrOversizedRequests() {
        for json in [
            #"{"title":"T","items":[]}"#,
            #"{"title":"","items":["a"]}"#,
            "not json",
            #"{"title":"T","items":[\#((1...501).map { "\"\($0)\"" }.joined(separator: ","))]}"#
        ] {
            XCTAssertThrowsError(try ChooserRequest.decode(Data(json.utf8)), json.prefix(40).description)
        }
    }

    func testEncodesChosenAndCancelledAnswers() throws {
        XCTAssertEqual(String(decoding: ChooserResult.chosen(2).encoded(), as: UTF8.self), #"{"index":2}"#)
        XCTAssertEqual(String(decoding: ChooserResult.cancelled.encoded(), as: UTF8.self), #"{"index":null}"#)
    }
}
