import Foundation
import XCTest
@testable import AppleBuildCore

final class AppReportListingTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!

    func testListsOnlyTheAppsReportsNewestFirstWithPlainLabels() throws {
        let entries = try AppReportListing.parse(json: fixture(), appName: "Sample Reader", timeZone: zone)

        XCTAssertEqual(entries.map(\.source), [
            "Sample Reader-2026-10-08-101605.000.ips",
            "Retired/Sample Reader.diskwrites_resource-2026-10-07-064709.ips",
            "Retired/Sample Reader-2026-10-07-063830.ips",
            "Retired/Sample Reader.cpu_resource-2026-10-07-063626.ips"
        ])
        XCTAssertEqual(entries.map(\.kind), [.crash, .diskWrites, .crash, .cpu])
        XCTAssertEqual(entries[1].label, "Too much disk writing, October 7 at 6:47 AM")
        XCTAssertEqual(entries[2].label, "Crash, October 7 at 6:38 AM")
        XCTAssertEqual(entries[3].label, "Too much CPU, October 7 at 6:36 AM")
    }

    func testShorterAppNameDoesNotMatchLongerNamesAndRegexCharactersAreLiteral() throws {
        XCTAssertEqual(
            try AppReportListing.parse(json: fixture(), appName: "Sample", timeZone: zone).map(\.source),
            ["Sample-2026-10-08-090000.ips"]
        )
        XCTAssertEqual(
            try AppReportListing.parse(json: fixture(), appName: "App+ (Beta)", timeZone: zone).map(\.source),
            ["App+ (Beta)-2026-10-08-120000.ips"]
        )
    }

    func testSinceKeepsReportsWithinTheClockToleranceOnly() throws {
        var components = DateComponents()
        components.timeZone = zone
        components.year = 2026; components.month = 10; components.day = 7
        components.hour = 6; components.minute = 38; components.second = 40
        let start = Calendar(identifier: .gregorian).date(from: components)!

        let entries = try AppReportListing.parse(json: fixture(), appName: "Sample Reader", timeZone: zone, since: start)

        XCTAssertEqual(entries.map(\.source), [
            "Sample Reader-2026-10-08-101605.000.ips",
            "Retired/Sample Reader.diskwrites_resource-2026-10-07-064709.ips",
            "Retired/Sample Reader-2026-10-07-063830.ips"
        ])
    }

    func testReportsWellBeforeTheStartAreNotBlamedOnTheNewRun() throws {
        var components = DateComponents()
        components.timeZone = zone
        components.year = 2026; components.month = 10; components.day = 7
        components.hour = 6; components.minute = 39; components.second = 0
        let start = Calendar(identifier: .gregorian).date(from: components)!

        let sources = try AppReportListing.parse(json: fixture(), appName: "Sample Reader", timeZone: zone, since: start)
            .map(\.source)

        XCTAssertFalse(sources.contains("Retired/Sample Reader-2026-10-07-063830.ips"))
    }

    func testUnknownBugTypeIsOtherReportEvenWithAPlainName() throws {
        let json = Data(#"{"result":{"files":[{"relativePath":"A-2026-10-08-090000.ips","metadata":{"extendedAttributes":{"bug_type":"999"}}}]}}"#.utf8)

        let entries = try AppReportListing.parse(json: json, appName: "A", timeZone: zone)

        XCTAssertEqual(entries.map(\.kind), [.other])
        XCTAssertEqual(entries.first?.label, "Other report, October 8 at 9:00 AM")
    }

    func testLimitAndMalformedInput() throws {
        XCTAssertEqual(try AppReportListing.parse(json: fixture(), appName: "Sample Reader", timeZone: zone, limit: 1).count, 1)
        XCTAssertEqual(try AppReportListing.parse(json: fixture(), appName: "Sample Reader", timeZone: zone, limit: nil).count, 4)
        XCTAssertThrowsError(try AppReportListing.parse(json: Data("nope".utf8), appName: "A", timeZone: zone))
    }

    private func fixture() -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try! Data(contentsOf: root.appendingPathComponent("Tests/fixtures/devicectl-files-systemCrashLogs.json"))
    }
}
