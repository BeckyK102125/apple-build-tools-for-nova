import Foundation
import XCTest
@testable import AppleBuildCore

final class ChooserLauncherTests: XCTestCase {
    private let reader = "/ext/Executables/Apple Build Reader.app"
    private let request = Data(#"{"title":"Select a build destination","items":["My Mac","iPhone"]}"#.utf8)

    func testOpensTheReaderInFrontAndReturnsTheChosenIndex() async throws {
        let runner = OpenFake(answer: #"{"index":1}"#)
        let index = try await ChooserLauncher(processRunner: runner).choose(readerPath: reader, request: request)

        XCTAssertEqual(index, 1)
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.command, "/usr/bin/open")
        XCTAssertEqual(Array(call.arguments.prefix(4)), ["-W", "-n", "-a", reader])
        XCTAssertEqual(Array(call.arguments.suffix(2)), ["--args", "--choose"])
        XCTAssertEqual(runner.sentRequest, request)
    }

    func testCancelReturnsNil() async throws {
        let index = try await ChooserLauncher(processRunner: OpenFake(answer: #"{"index":null}"#))
            .choose(readerPath: reader, request: request)
        XCTAssertNil(index)
    }

    func testFailuresThrowSoTheExtensionCanFallBack() async {
        for fake in [
            OpenFake(answer: #"{"index":1}"#, status: 1),
            OpenFake(answer: ""),
            OpenFake(answer: #"{"index":5}"#),
            OpenFake(answer: "garbage")
        ] {
            do {
                _ = try await ChooserLauncher(processRunner: fake).choose(readerPath: reader, request: request)
                XCTFail("Expected failure")
            } catch {
                XCTAssertTrue(error is ChooserLaunchError)
            }
        }
    }

    func testRejectsAnInvalidRequestWithoutOpening() async {
        let fake = OpenFake(answer: #"{"index":0}"#)
        do {
            _ = try await ChooserLauncher(processRunner: fake).choose(readerPath: reader, request: Data(#"{"title":"T","items":[]}"#.utf8))
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(fake.calls.isEmpty)
        }
    }
}

private final class OpenFake: ProcessRunning, @unchecked Sendable {
    private let answer: String
    private let status: Int32
    private let lock = NSLock()
    private var recorded: [ProcessSpecification] = []
    private var request: Data?

    init(answer: String, status: Int32 = 0) {
        self.answer = answer
        self.status = status
    }

    var calls: [ProcessSpecification] { lock.withLock { recorded } }
    var sentRequest: Data? { lock.withLock { request } }

    func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        let arguments = specification.arguments
        let input = arguments.firstIndex(of: "--stdin").map { try? Data(contentsOf: URL(fileURLWithPath: arguments[$0 + 1])) } ?? nil
        lock.withLock {
            recorded.append(specification)
            request = input
        }
        if let index = arguments.firstIndex(of: "--stdout") {
            try Data(answer.utf8).write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        return ProcessResult(status: status, standardOutput: "", standardError: "")
    }
}
