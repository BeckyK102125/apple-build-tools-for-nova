import XCTest
@testable import AppleBuildCore

final class BuildCommandBuilderTests: XCTestCase {
    func testBuildArgumentsAreExactAndNonMutating() throws {
        let selection = makeSelection()

        let specification = try BuildCommandBuilder().makeSpecification(
            action: .build,
            selection: selection,
            workspaceRoot: "/repo"
        )

        XCTAssertEqual(specification.command, "/usr/bin/xcrun")
        XCTAssertEqual(specification.arguments, [
            "xcodebuild", "-project", "/repo/BuildFixture.xcodeproj",
            "-scheme", "BuildFixture", "-configuration", "Debug",
            "-destination", "platform=macOS,arch=arm64,id=MAC-ID", "build"
        ])
        XCTAssertEqual(specification.environment, [
            "DEVELOPER_DIR": "/Applications/Xcode 27 rc.app/Contents/Developer"
        ])
        XCTAssertEqual(specification.workingDirectory, "/repo")
    }

    func testSimulatorDestinationReachesBuildWithoutInstallOrLaunch() throws {
        let output = """
        Destinations compatible with the "BuildFixture" scheme:
            { platform:iOS Simulator, id:SIM-A, OS:27.0, name:iPhone 17 }
        """
        let destination = try XCTUnwrap(XcodeMetadataService.parseDestinations(from: output).first)
        let selection = BuildSelection(
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            container: BuildContainer(
                kind: .project, path: "/repo/BuildFixture.xcodeproj", label: "BuildFixture"
            ),
            scheme: "BuildFixture", configuration: "Debug", destination: destination
        )
        let specification = try BuildCommandBuilder().makeSpecification(
            action: .test, selection: selection, workspaceRoot: "/repo"
        )
        XCTAssertEqual(specification.command, "/usr/bin/xcrun")
        XCTAssertEqual(specification.arguments, [
            "xcodebuild", "-project", "/repo/BuildFixture.xcodeproj",
            "-scheme", "BuildFixture", "-configuration", "Debug",
            "-destination", "platform=iOS Simulator,id=SIM-A", "test"
        ])
        XCTAssertEqual(specification.environment, [
            "DEVELOPER_DIR": "/Applications/Xcode 27 rc.app/Contents/Developer"
        ])
        XCTAssertEqual(specification.workingDirectory, "/repo")
    }

    func testWorkspaceUsesWorkspaceFlag() throws {
        let selection = makeSelection(kind: .workspace, path: "/repo/App.xcworkspace")

        let specification = try BuildCommandBuilder().makeSpecification(
            action: .clean,
            selection: selection,
            workspaceRoot: "/repo"
        )

        XCTAssertEqual(Array(specification.arguments.prefix(3)), [
            "xcodebuild", "-workspace", "/repo/App.xcworkspace"
        ])
        XCTAssertEqual(specification.arguments.last, "clean")
        XCTAssertFalse(specification.arguments.contains(where: {
            $0.localizedCaseInsensitiveContains("DerivedData") || $0 == "rm"
        }))
    }

    func testContainerOutsideWorkspaceIsRejected() {
        let selection = makeSelection(path: "/outside/App.xcodeproj")

        XCTAssertThrowsError(try BuildCommandBuilder().makeSpecification(
            action: .build,
            selection: selection,
            workspaceRoot: "/repo"
        )) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected project or workspace is outside the active workspace."
            )
        }
    }

    func testUnknownActionCannotBeDecoded() throws {
        for rawValue in ["archive", "Build", "run", ""] {
            let data = try JSONEncoder().encode(rawValue)
            XCTAssertThrowsError(try JSONDecoder().decode(XcodeAction.self, from: data))
        }
    }

    func testProvisioningMutationFlagsAreAbsentForEveryApprovedAction() throws {
        for action in XcodeAction.allCases {
            let arguments = try BuildCommandBuilder().makeSpecification(
                action: action,
                selection: makeSelection(),
                workspaceRoot: "/repo"
            ).arguments.map { $0.lowercased() }
            XCTAssertFalse(arguments.contains("-allowprovisioningupdates"))
            XCTAssertFalse(arguments.contains("-allowprovisioningdeviceregistration"))
        }
    }

    func testContainerOutsideWorkspaceIsRejectedForEveryApprovedAction() {
        for action in XcodeAction.allCases {
            XCTAssertThrowsError(try BuildCommandBuilder().makeSpecification(
                action: action,
                selection: makeSelection(path: "/outside/App.xcodeproj"),
                workspaceRoot: "/repo"
            ))
        }
    }

    func testCurrentSelectionMessageUsesTextForEveryValueAndMissingState() {
        let formatter = UserMessageFormatter()
        let saved = SavedBuildSelection(
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            containerKind: .workspace,
            containerPath: "/repo/App.xcworkspace",
            scheme: "App",
            configuration: nil,
            destinationLabel: "My Mac — macOS, arm64",
            destinationSpecifier: "platform=macOS,arch=arm64,id=MAC-ID"
        )
        let toolchain = Toolchain(
            version: "27.0",
            build: "27A266a",
            developerDirectory: saved.developerDirectory!,
            label: "Xcode 27.0, build 27A266a"
        )

        XCTAssertEqual(formatter.currentSelection(toolchain: toolchain, saved: saved), """
        Xcode: Xcode 27.0, build 27A266a, /Applications/Xcode 27 rc.app/Contents/Developer
        Project or Workspace: Workspace, /repo/App.xcworkspace
        Scheme: App
        Configuration: Not selected
        Destination: My Mac — macOS, arm64
        """)
    }

    func testPreflightErrorsAreNumbered() {
        XCTAssertEqual(
            UserMessageFormatter().preflightErrors(["First problem.", "Second problem."]),
            "Preflight failed.\n1. First problem.\n2. Second problem."
        )
    }

    private func makeSelection(
        kind: ContainerKind = .project,
        path: String = "/repo/BuildFixture.xcodeproj",
        scheme: String = "BuildFixture"
    ) -> BuildSelection {
        BuildSelection(
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            container: BuildContainer(kind: kind, path: path, label: "BuildFixture"),
            scheme: scheme,
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
}
