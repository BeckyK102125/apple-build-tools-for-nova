import Foundation

public enum AppReportKind: String, Codable, Sendable {
    case crash, cpu, diskWrites, fault, other

    var title: String {
        switch self {
        case .crash: return "Crash"
        case .cpu: return "Too much CPU"
        case .diskWrites: return "Too much disk writing"
        case .fault: return "Unexpected fault"
        case .other: return "Other report"
        }
    }

    static func from(bugType: String?, suffix: String?) -> AppReportKind {
        if let bugType {
            switch bugType {
            case "309": return .crash
            case "202": return .cpu
            case "145": return .diskWrites
            case "308": return .fault
            // A known file but an unlabelled kind must never be called a crash.
            default: return .other
            }
        }
        switch suffix {
        case nil: return .crash
        case "cpu_resource": return .cpu
        case "diskwrites_resource": return .diskWrites
        default: return .other
        }
    }
}

public struct AppReportEntry: Codable, Equatable, Sendable {
    public let source: String
    public let kind: AppReportKind
    public let label: String
    public let epochSeconds: Double
}

public struct AppReportListingError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?
}

public enum AppReportListing {
    // Covers whole-second file names and small Mac-to-iPhone clock differences, but not a previous run.
    public static let sinceTolerance: TimeInterval = 15

    public static func parse(
        json: Data,
        appName: String,
        timeZone: TimeZone,
        since: Date? = nil,
        limit: Int? = 10
    ) throws -> [AppReportEntry] {
        guard let listing = try? JSONDecoder().decode(Listing.self, from: json) else {
            throw AppReportListingError(errorDescription: "Your iPhone returned an unrecognized report list.")
        }
        let pattern = "^" + NSRegularExpression.escapedPattern(for: appName)
            + #"(?:\.([A-Za-z_]+))?-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})(?:\.\d+)?\.ips$"#
        let expression = try NSRegularExpression(pattern: pattern)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let threshold = since.map { $0.addingTimeInterval(-sinceTolerance) }

        var entries: [AppReportEntry] = []
        for file in listing.result.files {
            let name = (file.relativePath as NSString).lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            guard let match = expression.firstMatch(in: name, range: range) else { continue }
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: name).map { String(name[$0]) }
            }
            var components = DateComponents()
            components.year = Int(group(2)!); components.month = Int(group(3)!); components.day = Int(group(4)!)
            components.hour = Int(group(5)!); components.minute = Int(group(6)!); components.second = Int(group(7)!)
            guard let date = calendar.date(from: components) else { continue }
            if let threshold, date < threshold { continue }
            let kind = AppReportKind.from(
                bugType: file.metadata?.extendedAttributes?["bug_type"],
                suffix: group(1)
            )
            entries.append(AppReportEntry(
                source: file.relativePath,
                kind: kind,
                label: "\(kind.title), \(labelFormatter(timeZone).string(from: date))",
                epochSeconds: date.timeIntervalSince1970
            ))
        }
        entries.sort { $0.epochSeconds > $1.epochSeconds }
        if let limit { return Array(entries.prefix(limit)) }
        return entries
    }

    private static func labelFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM d 'at' h:mm a"
        return formatter
    }

    private struct Listing: Decodable {
        struct Result: Decodable { let files: [File] }
        struct File: Decodable {
            let relativePath: String
            let metadata: Metadata?
        }
        struct Metadata: Decodable {
            let extendedAttributes: [String: String]?
        }
        let result: Result
    }
}
