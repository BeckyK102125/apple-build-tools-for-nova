import Foundation
import XCTest
@testable import AppleBuildCore

final class IPSReportTests: XCTestCase {
    func testDiskWritesReportSummarizesInPlainWords() throws {
        let report = try IPSReport.parse(fixture("ips-diskwrites.ips"))

        XCTAssertEqual(report.appName, "Sample Reader")
        XCTAssertEqual(report.kind, .diskWrites)
        XCTAssertTrue(report.summary.hasPrefix("Sample Reader wrote too much data to storage."))
        XCTAssertTrue(report.summary.contains("4305.04 MB"))
        XCTAssertEqual(report.details, [
            IPSDetail(label: "App version", value: "1.0.1 (13)"),
            IPSDetail(label: "Bundle ID", value: "com.example.sample-reader"),
            IPSDetail(label: "iPhone model", value: "iPhone16,1"),
            IPSDetail(label: "iOS version", value: "iPhone OS 27.2 (24B5089g)")
        ])
        XCTAssertEqual(report.fullText, fixture("ips-diskwrites.ips"))
    }

    func testCrashReportNamesExceptionReasonAndTopFrames() throws {
        let report = try IPSReport.parse(fixture("ips-crash.ips"))

        XCTAssertEqual(report.kind, .crash)
        XCTAssertEqual(
            report.summary,
            "Sample App crashed with EXC_BREAKPOINT (SIGTRAP). Reason: Trace/BPT trap: 5. "
                + "Top of the crashed thread: libswiftCore.dylib _assertionFailure(_:_:file:line:flags:); "
                + "Sample App +4242; Sample App +5151."
        )
        XCTAssertEqual(report.details.first(where: { $0.label == "iPhone model" })?.value, "iPhone16,1")
    }

    func testUnknownKindAndMalformedInput() throws {
        let other = try IPSReport.parse(#"{"app_name":"A","bug_type":"999","os_version":"iOS"}"# + "\nbody")
        XCTAssertEqual(other.kind, .other)
        XCTAssertEqual(other.summary, "iOS recorded a report about A.")
        XCTAssertThrowsError(try IPSReport.parse("not a report"))
        XCTAssertThrowsError(try IPSReport.parse(""))
    }

    private func fixture(_ name: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try! String(contentsOf: root.appendingPathComponent("Tests/fixtures/\(name)"), encoding: .utf8)
    }
}
