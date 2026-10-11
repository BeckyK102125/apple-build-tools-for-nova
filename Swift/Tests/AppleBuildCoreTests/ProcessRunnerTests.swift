import XCTest
@testable import AppleBuildCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStandardOutputWithoutShell() async throws {
        let specification = ProcessSpecification(
            command: "/usr/bin/printf",
            arguments: ["%s", "captured output"],
            environment: [:],
            workingDirectory: "/private/tmp"
        )

        let result = try await ProcessRunner().run(specification)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.standardOutput, "captured output")
        XCTAssertEqual(result.standardError, "")
    }

    func testReturnsNonzeroStatusInsteadOfThrowing() async throws {
        let specification = ProcessSpecification(
            command: "/usr/bin/false",
            arguments: [],
            environment: [:],
            workingDirectory: "/private/tmp"
        )

        let result = try await ProcessRunner().run(specification)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(result.standardOutput, "")
        XCTAssertEqual(result.standardError, "")
    }
}
