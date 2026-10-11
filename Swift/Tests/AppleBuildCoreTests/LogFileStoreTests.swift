import Foundation
import XCTest
@testable import AppleBuildCore

final class LogFileStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LogFileStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWritesDatedFileInSanitizedAppFolder() throws {
        let store = LogFileStore(root: root, now: { Date(timeIntervalSince1970: 1_791_569_405) },
                                 timeZone: TimeZone(identifier: "America/New_York")!)

        let path = try store.write(appName: "../Sample/Reader", title: "App Console", contents: "# Hi\n")

        XCTAssertEqual(path, root.appendingPathComponent("Sample-Reader/2026-10-09 14-10-05 App Console.md").path)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# Hi\n")
    }

    func testSameSecondGetsANewNameAndOnlyNewestKeepRemain() throws {
        let clock = TickClock(start: 1_791_569_405)
        let store = LogFileStore(root: root, keep: 3, now: { clock.next() },
                                 timeZone: TimeZone(identifier: "UTC")!)
        for _ in 0..<5 { _ = try store.write(appName: "App", title: "Report", contents: "x") }
        let fixed = LogFileStore(root: root, keep: 3, now: { Date(timeIntervalSince1970: 1_791_569_405 + 5) },
                                 timeZone: TimeZone(identifier: "UTC")!)
        let second = try fixed.write(appName: "App", title: "Report", contents: "y")

        let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("App").path).sorted()
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(second.hasSuffix(" Report 2.md"))
        XCTAssertFalse(names.contains("2026-10-09 18-10-06 Report.md"))
    }
}

private final class TickClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval

    init(start: TimeInterval) { seconds = start }

    func next() -> Date {
        lock.withLock {
            seconds += 1
            return Date(timeIntervalSince1970: seconds)
        }
    }
}
