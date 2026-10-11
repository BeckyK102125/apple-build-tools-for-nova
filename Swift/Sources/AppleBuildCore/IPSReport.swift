import Foundation

public struct IPSDetail: Equatable, Sendable {
    public let label: String
    public let value: String
    public init(label: String, value: String) { self.label = label; self.value = value }
}

public struct IPSReportError: HelperDomainFailure, Equatable, Sendable {
    public let errorDescription: String?
}

public struct IPSReport: Equatable, Sendable {
    public let appName: String
    public let kind: AppReportKind
    public let summary: String
    public let details: [IPSDetail]
    public let fullText: String

    public init(appName: String, kind: AppReportKind, summary: String, details: [IPSDetail], fullText: String) {
        self.appName = appName; self.kind = kind; self.summary = summary
        self.details = details; self.fullText = fullText
    }

    public static func parse(_ text: String) throws -> IPSReport {
        let failure = IPSReportError(errorDescription: "This report is not in a format Apple Build Tools can read.")
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first,
              let header = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else {
            throw failure
        }
        let body = parts.count > 1 ? String(parts[1]) : ""
        let appName = (header["app_name"] as? String) ?? (header["name"] as? String) ?? "The app"
        let kind = AppReportKind.from(bugType: header["bug_type"] as? String, suffix: "unknown")
        let crashBody = kind == .crash
            ? (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
            : nil

        var details: [IPSDetail] = []
        if let version = header["app_version"] as? String {
            let build = (header["build_version"] as? String).map { " (\($0))" } ?? ""
            details.append(IPSDetail(label: "App version", value: version + build))
        }
        if let bundle = header["bundleID"] as? String { details.append(IPSDetail(label: "Bundle ID", value: bundle)) }
        if let model = (crashBody?["modelCode"] as? String) ?? field("Hardware model", in: body) {
            details.append(IPSDetail(label: "iPhone model", value: model))
        }
        if let os = header["os_version"] as? String { details.append(IPSDetail(label: "iOS version", value: os)) }

        return IPSReport(
            appName: appName, kind: kind,
            summary: summary(kind: kind, appName: appName, body: body, crash: crashBody),
            details: details, fullText: text
        )
    }

    private static func summary(kind: AppReportKind, appName: String, body: String, crash: [String: Any]?) -> String {
        switch kind {
        case .diskWrites:
            let writes = field("Writes", in: body).map { " \($0)." } ?? ""
            return "\(appName) wrote too much data to storage.\(writes)"
        case .cpu:
            let cpu = field("CPU", in: body).map { " \($0)." } ?? ""
            return "\(appName) used too much CPU.\(cpu)"
        case .fault:
            return "\(appName) hit an unexpected fault."
        case .crash:
            guard let crash else { return "\(appName) crashed." }
            let exception = crash["exception"] as? [String: Any]
            let type = exception?["type"] as? String ?? "an unknown exception"
            let signal = (exception?["signal"] as? String).map { " (\($0))" } ?? ""
            let reason = ((crash["termination"] as? [String: Any])?["indicator"] as? String).map { " Reason: \($0)." } ?? ""
            let frames = topFrames(crash).map { " Top of the crashed thread: \($0.joined(separator: "; "))." } ?? ""
            return "\(appName) crashed with \(type)\(signal).\(reason)\(frames)"
        case .other:
            return "iOS recorded a report about \(appName)."
        }
    }

    private static func topFrames(_ crash: [String: Any]) -> [String]? {
        guard let threads = crash["threads"] as? [[String: Any]],
              let thread = threads.first(where: { ($0["triggered"] as? Bool) == true }) ?? threads.first,
              let frames = thread["frames"] as? [[String: Any]], !frames.isEmpty else { return nil }
        let images = (crash["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String ?? "unknown" } ?? []
        return frames.prefix(5).map { frame in
            let index = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(index) ? images[index] : "unknown"
            if let symbol = frame["symbol"] as? String { return "\(image) \(symbol)" }
            return "\(image) +\(frame["imageOffset"] as? Int ?? 0)"
        }
    }

    private static func field(_ name: String, in body: String) -> String? {
        for line in body.split(separator: "\n") where line.hasPrefix(name + ":") {
            let value = line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
