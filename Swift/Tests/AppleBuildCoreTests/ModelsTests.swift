import Foundation
import XCTest
@testable import AppleBuildCore

final class ModelsTests: XCTestCase {
    func testBuildContainerRoundTripsThroughJSON() throws {
        let expected = BuildContainer(
            kind: .workspace,
            path: "/repo/App.xcworkspace",
            label: "App.xcworkspace"
        )

        let encoded = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(BuildContainer.self, from: encoded)

        XCTAssertEqual(decoded, expected)
    }

    func testDomainErrorResponseRoundTripsThroughJSON() throws {
        let expected = HelperResponse<String>(
            ok: false,
            value: nil,
            errors: ["No helper command was supplied."]
        )

        let encoded = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(HelperResponse<String>.self, from: encoded)

        XCTAssertFalse(decoded.ok)
        XCTAssertNil(decoded.value)
        XCTAssertEqual(decoded.errors, ["No helper command was supplied."])
    }
}
