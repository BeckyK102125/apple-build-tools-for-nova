import Foundation

/// A list to choose from, sent by an extension (through its helper) on standard input.
public struct ChooserRequest: Codable, Equatable, Sendable {
    public static let maxItems = 500
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }

    public static func decode(_ data: Data) throws -> ChooserRequest {
        let request = try JSONDecoder().decode(ChooserRequest.self, from: data)
        guard !request.title.isEmpty, !request.items.isEmpty, request.items.count <= maxItems else {
            throw ChooserError.invalidRequest
        }
        return request
    }
}

public enum ChooserError: Error, Equatable {
    case invalidRequest
}

/// The answer written to standard output: the chosen index, or null when cancelled.
public enum ChooserResult: Equatable, Sendable {
    case chosen(Int)
    case cancelled

    public func encoded() -> Data {
        switch self {
        case let .chosen(index): return Data("{\"index\":\(index)}".utf8)
        case .cancelled: return Data("{\"index\":null}".utf8)
        }
    }
}
