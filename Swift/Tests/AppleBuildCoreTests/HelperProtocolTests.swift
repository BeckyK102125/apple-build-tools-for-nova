import Foundation
import XCTest
@testable import AppleBuildCore

final class HelperProtocolTests: XCTestCase {
    func testParsesContainersCommand() throws {
        let command = try HelperCommand.parse(arguments: [
            "containers", "--workspace-root", "/repo"
        ])

        XCTAssertEqual(command, .containers(workspaceRoot: "/repo"))
    }

    func testParsesToolchainsCommandWithSavedDirectory() throws {
        let command = try HelperCommand.parse(arguments: [
            "toolchains",
            "--applications", "/Applications",
            "--saved-developer-directory", "/Applications/Xcode 27 rc.app/Contents/Developer"
        ])

        XCTAssertEqual(
            command,
            .toolchains(
                applications: "/Applications",
                savedDeveloperDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer"
            )
        )
    }

    func testParsesDestinationCommand() throws {
        let command = try HelperCommand.parse(arguments: [
            "destinations",
            "--workspace-root", "/repo",
            "--developer-directory", "/Applications/Xcode.app/Contents/Developer",
            "--container-kind", "workspace",
            "--container-path", "/repo/App.xcworkspace",
            "--scheme", "App"
        ])

        XCTAssertEqual(
            command,
            .destinations(
                workspaceRoot: "/repo",
                developerDirectory: "/Applications/Xcode.app/Contents/Developer",
                containerKind: .workspace,
                containerPath: "/repo/App.xcworkspace",
                scheme: "App"
            )
        )
    }

    func testParsesProjectNavigatorCommandWithoutRequiringXcode() throws {
        let command = try HelperCommand.parse(arguments: [
            "project-navigator",
            "--workspace-root", "/repo",
            "--container-kind", "project",
            "--container-path", "/repo/App.xcodeproj"
        ])

        XCTAssertEqual(
            command,
            .projectNavigator(
                workspaceRoot: "/repo",
                containerKind: .project,
                containerPath: "/repo/App.xcodeproj"
            )
        )
    }

    func testParsesEveryApprovedPrepareAction() throws {
        for action in XcodeAction.allCases {
            let command = try HelperCommand.parse(arguments: [
                "prepare-action",
                "--action", action.rawValue,
                "--workspace-root", "/repo",
                "--selection-json", "{}"
            ])
            XCTAssertEqual(command, .prepareAction(
                action: action,
                workspaceRoot: "/repo",
                selectionJSON: "{}"
            ))
        }
    }

    func testParsesSigningStatusCommand() throws {
        let command = try HelperCommand.parse(arguments: [
            "signing-status", "--workspace-root", "/repo", "--selection-json", "{}"
        ])

        XCTAssertEqual(command, .signingStatus(workspaceRoot: "/repo", selectionJSON: "{}"))
    }

    func testParsesPrepareDeviceRunCommand() throws {
        let command = try HelperCommand.parse(arguments: [
            "prepare-device-run", "--workspace-root", "/repo", "--selection-json", "{}"
        ])

        XCTAssertEqual(command, .prepareDeviceRun(workspaceRoot: "/repo", selectionJSON: "{}"))
    }

    func testPrepareDeviceRunRejectsExtraOptionsAndRelativeRoots() {
        let invalidArguments = [
            ["prepare-device-run", "--workspace-root", "/repo", "--selection-json", "{}", "--action", "build"],
            ["prepare-device-run", "--workspace-root", "repo", "--selection-json", "{}"],
            ["prepare-device-run", "--workspace-root", "/repo"]
        ]
        for arguments in invalidArguments {
            XCTAssertThrowsError(try HelperCommand.parse(arguments: arguments))
        }
    }

    func testParsesDiagnosticsCommands() throws {
        XCTAssertEqual(
            try HelperCommand.parse(arguments: ["app-reports", "--workspace-root", "/repo", "--selection-json", "{}", "--since-epoch", "1791569405"]),
            .appReports(workspaceRoot: "/repo", selectionJSON: "{}", sinceEpoch: 1_791_569_405)
        )
        XCTAssertEqual(
            try HelperCommand.parse(arguments: ["app-report", "--workspace-root", "/repo", "--selection-json", "{}", "--source", "A-2026-10-07-063830.ips"]),
            .appReport(workspaceRoot: "/repo", selectionJSON: "{}", source: "A-2026-10-07-063830.ips")
        )
        XCTAssertEqual(
            try HelperCommand.parse(arguments: ["write-console", "--workspace-root", "/repo", "--selection-json", "{}"]),
            .writeConsole(workspaceRoot: "/repo", selectionJSON: "{}")
        )
    }

    func testDiagnosticsCommandsRejectBadInput() {
        for arguments in [
            ["app-reports", "--workspace-root", "/repo", "--selection-json", "{}", "--since-epoch", "soon"],
            ["app-report", "--workspace-root", "/repo", "--selection-json", "{}"],
            ["app-report", "--workspace-root", "/repo", "--selection-json", "{}", "--source", "/etc/passwd"],
            ["write-console", "--workspace-root", "repo", "--selection-json", "{}"]
        ] {
            XCTAssertThrowsError(try HelperCommand.parse(arguments: arguments), "\(arguments)")
        }
    }

    func testParsesWriteDocumentCommand() throws {
        XCTAssertEqual(
            try HelperCommand.parse(arguments: ["write-document", "--app-name", "SampleApp", "--title", "Apple Build Command Report"]),
            .writeDocument(appName: "SampleApp", title: "Apple Build Command Report")
        )
        XCTAssertThrowsError(try HelperCommand.parse(arguments: ["write-document", "--app-name", "SampleApp"]))
    }

    func testParsesMacRunCommand() throws {
        XCTAssertEqual(
            try HelperCommand.parse(arguments: ["mac-run", "--app", "/tmp/DD/Poster.app"]),
            .macRun(appPath: "/tmp/DD/Poster.app")
        )
        for arguments in [["mac-run"], ["mac-run", "--app", "Poster.app"], ["mac-run", "--app", "/bin/sh"]] {
            XCTAssertThrowsError(try HelperCommand.parse(arguments: arguments), "\(arguments)")
        }
    }

    func testParsesChooseCommand() throws {
        XCTAssertEqual(
            try HelperCommand.parse(arguments: ["choose", "--reader", "/ext/Executables/Apple Build Reader.app"]),
            .choose(readerPath: "/ext/Executables/Apple Build Reader.app")
        )
        for arguments in [["choose"], ["choose", "--reader", "relative.app"], ["choose", "--reader", "/bin/sh"]] {
            XCTAssertThrowsError(try HelperCommand.parse(arguments: arguments), "\(arguments)")
        }
    }

    func testSigningStatusRejectsUnknownOptions() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "signing-status", "--workspace-root", "/repo",
            "--selection-json", "{}", "--action", "build"
        ]))
    }

    func testPrepareActionRejectsMissingDuplicateCaseVariantAndUnknownActions() {
        let invalidArguments = [
            ["prepare-action", "--workspace-root", "/repo", "--selection-json", "{}"],
            ["prepare-action", "--action", "build", "--action", "test", "--workspace-root", "/repo", "--selection-json", "{}"],
            ["prepare-action", "--action", "Build", "--workspace-root", "/repo", "--selection-json", "{}"],
            ["prepare-action", "--action", "archive", "--workspace-root", "/repo", "--selection-json", "{}"]
        ]
        for arguments in invalidArguments {
            XCTAssertThrowsError(try HelperCommand.parse(arguments: arguments))
        }
    }

    func testPrepareActionRequiresAbsoluteWorkspacePath() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "prepare-action", "--action", "build",
            "--workspace-root", "repo", "--selection-json", "{}"
        ])) { error in
            XCTAssertEqual(error.localizedDescription, "--workspace-root must be an absolute path.")
        }
    }

    func testRejectsMissingWorkspaceRoot() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: ["containers"])) { error in
            XCTAssertEqual(error.localizedDescription, "containers requires --workspace-root.")
        }
    }

    func testRejectsDuplicateOption() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "containers", "--workspace-root", "/repo", "--workspace-root", "/other"
        ])) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Option --workspace-root was provided more than once for containers."
            )
        }
    }

    func testRejectsMissingOptionValue() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "containers", "--workspace-root"
        ])) { error in
            XCTAssertEqual(error.localizedDescription, "--workspace-root requires a value for containers.")
        }
    }

    func testRejectsRelativePaths() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "containers", "--workspace-root", "repo"
        ])) { error in
            XCTAssertEqual(error.localizedDescription, "--workspace-root must be an absolute path.")
        }
    }

    func testRejectsInvalidContainerKind() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "schemes",
            "--workspace-root", "/repo",
            "--developer-directory", "/Applications/Xcode.app/Contents/Developer",
            "--container-kind", "archive",
            "--container-path", "/repo/App.xcodeproj"
        ])) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "--container-kind must be workspace or project."
            )
        }
    }

    func testRejectsUnknownOption() {
        XCTAssertThrowsError(try HelperCommand.parse(arguments: [
            "containers", "--workspace-root", "/repo", "--unknown", "value"
        ])) { error in
            XCTAssertEqual(error.localizedDescription, "Unknown option --unknown for containers.")
        }
    }

    func testEncodesCompactSortedJSONWithoutEscapingSlashes() throws {
        let data = try JSONEmitter.encode(HelperResponse(ok: true, value: "/repo", errors: []))

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"errors":[],"ok":true,"value":"/repo"}"#
        )
    }
}
