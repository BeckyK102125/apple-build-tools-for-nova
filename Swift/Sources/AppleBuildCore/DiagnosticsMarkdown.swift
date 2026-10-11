import Foundation

public enum ConsoleState: String, Codable, Sendable {
    case running, checking, ended, crashed, stopped, listeningFailed
}

public struct ConsoleCapture: Codable, Equatable, Sendable {
    public let appName: String
    public let deviceName: String
    public let startedAt: String
    public let endedAt: String?
    public let state: ConsoleState
    public let lines: [String]
    public let droppedLines: Int
    public let crashSource: String?

    public init(appName: String, deviceName: String, startedAt: String, endedAt: String?,
                state: ConsoleState, lines: [String], droppedLines: Int, crashSource: String?) {
        self.appName = appName; self.deviceName = deviceName; self.startedAt = startedAt
        self.endedAt = endedAt; self.state = state; self.lines = lines
        self.droppedLines = droppedLines; self.crashSource = crashSource
    }
}

public enum DiagnosticsMarkdown {
    static let errorPattern = try! NSRegularExpression(pattern: #"\b(error|fault)\b"#, options: .caseInsensitive)
    static let warningPattern = try! NSRegularExpression(pattern: #"\bwarning\b"#, options: .caseInsensitive)

    public static func report(_ report: IPSReport, label: String) -> String {
        let parts = label.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let title = parts.count == 2 ? "\(parts[0]): \(report.appName), \(parts[1])" : "\(label): \(report.appName)"
        var lines = ["# \(title)", "", "## What happened", "", report.summary, "", "## Details", ""]
        lines += report.details.map { "- \($0.label): \($0.value)" }
        lines += ["", "## Full report", "", fenced(report.fullText), ""]
        return lines.joined(separator: "\n")
    }

    public static func console(_ capture: ConsoleCapture, crash: IPSReport?, timeZone: TimeZone = .current) -> String {
        let flagged = capture.lines.filter { matches(errorPattern, $0) || matches(warningPattern, $0) }
        let errors = capture.lines.filter { matches(errorPattern, $0) }.count
        let warnings = capture.lines.filter { !matches(errorPattern, $0) && matches(warningPattern, $0) }.count

        var summary = ["Started \(readable(capture.startedAt, timeZone))."]
        switch capture.state {
        case .running: summary.append("The app is still running.")
        case .checking: summary.append("The app stopped. Checking your iPhone for a crash report.")
        case .ended: summary.append("The app quit.")
        case .crashed: summary.append("The app crashed.")
        case .stopped: summary.append("You stopped listening.")
        case .listeningFailed: summary.append("Listening stopped unexpectedly.")
        }
        if let ended = capture.endedAt { summary.append("Ended \(readable(ended, timeZone)).") }
        summary.append(errors + warnings == 0
            ? "No errors or warnings."
            : "\(count(errors, "error")) and \(count(warnings, "warning")).")
        if capture.droppedLines > 0 { summary.append("Showing the newest 10,000 lines.") }

        var lines = ["# App Console: \(capture.appName) on \(capture.deviceName)", "", "## Summary", "",
                     summary.joined(separator: " "), "", "## Errors and warnings", ""]
        lines.append(flagged.isEmpty ? "No errors or warnings." : fenced(flagged.joined(separator: "\n")))
        lines += ["", "## Full output", ""]
        lines.append(capture.lines.isEmpty ? "The app printed nothing." : fenced(capture.lines.joined(separator: "\n")))
        if let crash {
            lines += ["", "## Crash report", "", crash.summary, "", fenced(crash.fullText)]
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // "2026-10-09T18:10:05.123Z" becomes "October 9 at 2:10:05 PM" in the Mac's time zone.
    static func readable(_ timestamp: String, _ timeZone: TimeZone) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let date = parser.date(from: timestamp) ?? fallback.date(from: timestamp) else { return timestamp }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM d 'at' h:mm:ss a"
        return formatter.string(from: date)
    }

    static func matches(_ expression: NSRegularExpression, _ line: String) -> Bool {
        expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    // A fence one backtick longer than any backtick run in the text keeps headings intact.
    static func fenced(_ text: String) -> String {
        var longest = 0, current = 0
        for character in text {
            if character == "`" { current += 1; longest = max(longest, current) } else { current = 0 }
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\n\(text)\n\(fence)"
    }
}
