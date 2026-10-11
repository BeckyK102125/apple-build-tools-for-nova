import XCTest
@testable import AppleBuildCore

final class DiagnosticsMarkdownTests: XCTestCase {
    func testReportDocumentHasTheAgreedHeadingsInOrder() throws {
        let report = IPSReport(
            appName: "Sample App", kind: .crash, summary: "Sample App crashed.",
            details: [IPSDetail(label: "App version", value: "1.0 (1)")], fullText: "raw ``` text"
        )
        let markdown = DiagnosticsMarkdown.report(report, label: "Crash, October 7 at 6:38 AM")

        XCTAssertEqual(headings(markdown), [
            "# Crash: Sample App, October 7 at 6:38 AM",
            "## What happened", "## Details", "## Full report"
        ])
        XCTAssertTrue(markdown.contains("- App version: 1.0 (1)"))
        XCTAssertTrue(markdown.contains("````\nraw ``` text\n````"))
    }

    func testConsoleDocumentSortsErrorsAndStatesEachCondition() {
        let capture = ConsoleCapture(
            appName: "Sample App", deviceName: "Sam’s iPhone",
            startedAt: "2026-10-09T14:10:05-04:00", endedAt: nil, state: .running,
            lines: ["Launched", "Error: could not open file", "warning: slow", "", "fault in audio"],
            droppedLines: 3, crashSource: nil
        )
        let markdown = DiagnosticsMarkdown.console(capture, crash: nil)

        XCTAssertEqual(headings(markdown), [
            "# App Console: Sample App on Sam’s iPhone",
            "## Summary", "## Errors and warnings", "## Full output"
        ])
        XCTAssertTrue(markdown.contains("The app is still running."))
        XCTAssertTrue(markdown.contains("2 errors and 1 warning."))
        XCTAssertTrue(markdown.contains("Showing the newest 10,000 lines."))
        XCTAssertTrue(markdown.contains("Error: could not open file\nwarning: slow\nfault in audio"))
    }

    func testConsoleTimesAreReadInLocalTime() {
        let capture = ConsoleCapture(
            appName: "A", deviceName: "D", startedAt: "2026-10-09T18:10:05.123Z",
            endedAt: "2026-10-09T18:12:00.000Z", state: .ended, lines: [], droppedLines: 0, crashSource: nil
        )
        let markdown = DiagnosticsMarkdown.console(capture, crash: nil, timeZone: TimeZone(identifier: "America/New_York")!)

        XCTAssertTrue(markdown.contains("Started October 9 at 2:10:05 PM."))
        XCTAssertTrue(markdown.contains("Ended October 9 at 2:12:00 PM."))
        XCTAssertFalse(markdown.contains("2026-10-09T"))
    }

    func testConsoleWhileCheckingForACrash() {
        let capture = ConsoleCapture(
            appName: "A", deviceName: "D", startedAt: "2026-10-09T18:10:05.123Z",
            endedAt: nil, state: .checking, lines: [], droppedLines: 0, crashSource: nil
        )
        XCTAssertTrue(DiagnosticsMarkdown.console(capture, crash: nil)
            .contains("The app stopped. Checking your iPhone for a crash report."))
    }

    func testConsoleStatesForStoppedCrashedAndEmpty() {
        func capture(_ state: ConsoleState, lines: [String] = []) -> ConsoleCapture {
            ConsoleCapture(appName: "A", deviceName: "D", startedAt: "2026-10-09T14:10:05-04:00",
                           endedAt: "2026-10-09T14:12:00-04:00", state: state, lines: lines,
                           droppedLines: 0, crashSource: nil)
        }
        XCTAssertTrue(DiagnosticsMarkdown.console(capture(.stopped), crash: nil).contains("You stopped listening."))
        XCTAssertTrue(DiagnosticsMarkdown.console(capture(.ended), crash: nil).contains("The app quit."))
        XCTAssertTrue(DiagnosticsMarkdown.console(capture(.listeningFailed), crash: nil).contains("Listening stopped unexpectedly."))
        XCTAssertTrue(DiagnosticsMarkdown.console(capture(.ended), crash: nil).contains("No errors or warnings."))
        XCTAssertTrue(DiagnosticsMarkdown.console(capture(.ended), crash: nil).contains("The app printed nothing."))
        let crash = IPSReport(appName: "A", kind: .crash, summary: "A crashed.", details: [], fullText: "raw")
        let crashed = DiagnosticsMarkdown.console(capture(.crashed), crash: crash)
        XCTAssertEqual(headings(crashed).last, "## Crash report")
        XCTAssertTrue(crashed.contains("The app crashed."))
        XCTAssertFalse(headings(DiagnosticsMarkdown.console(capture(.ended, lines: ["# not a heading"]), crash: nil)).contains("# not a heading"))
    }

    private func headings(_ markdown: String) -> [String] {
        var inFence = false
        return markdown.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); return nil }
            return !inFence && line.hasPrefix("#") ? String(line) : nil
        }
    }
}
