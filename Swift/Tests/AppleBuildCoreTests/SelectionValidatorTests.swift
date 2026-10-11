import XCTest
@testable import AppleBuildCore

final class SelectionValidatorTests: XCTestCase {
    func testMissingDestinationFailsBeforeBuild() {
        let selection = makeSelection()
        let current = makeChoices(destinations: [])

        XCTAssertEqual(
            SelectionValidator().validate(selection, against: current),
            ValidationResult(valid: false, errors: [
                "The saved destination is no longer available. Select Destination again."
            ])
        )
    }

    func testReportsEveryStaleValueInFixedSelectionOrder() {
        let selection = makeSelection()
        let current = AvailableBuildChoices(
            toolchains: [],
            containers: [],
            schemes: [],
            configurations: [],
            destinations: []
        )

        XCTAssertEqual(SelectionValidator().validate(selection, against: current).errors, [
            "The saved Xcode is no longer available. Select Xcode again.",
            "The saved project or workspace is no longer available. Select Project or Workspace again.",
            "The saved scheme is no longer available. Select Scheme again.",
            "The saved configuration is no longer available. Select Configuration again.",
            "The saved destination is no longer available. Select Destination again."
        ])
    }

    func testContainerComparisonUsesStandardizedPath() {
        let selection = makeSelection(containerPath: "/repo/Nested/../BuildFixture.xcodeproj")

        XCTAssertEqual(
            SelectionValidator().validate(selection, against: makeChoices()).valid,
            true
        )
    }

    private func makeSelection(containerPath: String = "/repo/BuildFixture.xcodeproj") -> BuildSelection {
        BuildSelection(
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            container: BuildContainer(
                kind: .project,
                path: containerPath,
                label: "BuildFixture.xcodeproj"
            ),
            scheme: "BuildFixture",
            configuration: "Debug",
            destination: Destination(
                label: "My Mac — macOS, arm64",
                specifier: "platform=macOS,arch=arm64,id=MAC-ID",
                platform: "macOS",
                id: "MAC-ID",
                generic: false
            )
        )
    }

    private func makeChoices(destinations: [Destination]? = nil) -> AvailableBuildChoices {
        let selection = makeSelection()
        return AvailableBuildChoices(
            toolchains: [Toolchain(
                version: "27.0",
                build: "27A266a",
                developerDirectory: selection.developerDirectory,
                label: "Xcode 27.0, build 27A266a"
            )],
            containers: [selection.container],
            schemes: [selection.scheme],
            configurations: [selection.configuration],
            destinations: destinations ?? [selection.destination]
        )
    }
}
