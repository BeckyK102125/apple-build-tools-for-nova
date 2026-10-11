import Foundation
import Observation

@MainActor
@Observable
public final class ReaderModel {
    public private(set) var document: ReaderDocument?
    public private(set) var revision = 0

    public init() {}

    public func open(_ url: URL) {
        show(ReaderDocument.load(from: url))
    }

    public func show(_ document: ReaderDocument) {
        self.document = document
        revision += 1
    }
}
