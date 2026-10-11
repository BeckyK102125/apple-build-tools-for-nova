import Foundation
import XCTest
@testable import AppleBuildCore

final class SigningStatusServiceTests: XCTestCase {
    func testParsesAutomaticSigningAndAllowlistedFields() throws {
        let snapshot = try SigningStatusService.parse(
            output: fixture("build-settings-signing-automatic.json")
        )

        XCTAssertEqual(snapshot.overallStatus, .ready)
        XCTAssertEqual(snapshot.targets.count, 1)
        let target = try XCTUnwrap(snapshot.targets.first)
        XCTAssertEqual(target.targetName, "PosterApp")
        XCTAssertEqual(target.bundleIdentifier, "com.example.poster")
        XCTAssertEqual(target.signingStyle, "Automatic")
        XCTAssertEqual(target.developmentTeam, "TEAM123456")
        XCTAssertEqual(target.signingIdentity, "Apple Development")
        XCTAssertEqual(target.signingAllowed, true)
        XCTAssertEqual(target.signingRequired, true)
        XCTAssertNil(target.provisioningProfile)
        XCTAssertEqual(target.entitlements, "PosterApp/PosterApp.entitlements")
        XCTAssertEqual(target.sdkRoot, "iphoneos")
        XCTAssertEqual(target.status, .ready)
        XCTAssertFalse(String(describing: snapshot).contains("UNEXPECTED_SECRET"))
        XCTAssertFalse(String(describing: snapshot).contains("private-key"))
    }

    func testParsesManualSigningWithoutExposingProfileIdentifiers() throws {
        let snapshot = try SigningStatusService.parse(
            output: fixture("build-settings-signing-manual.json")
        )

        XCTAssertEqual(snapshot.overallStatus, .ready)
        let target = try XCTUnwrap(snapshot.targets.first)
        XCTAssertEqual(target.status, .ready)
        XCTAssertEqual(target.provisioningProfile, "Configured")
        XCTAssertFalse(target.provisioningProfile?.contains("/Users/") == true)
        XCTAssertFalse(target.provisioningProfile?.contains("12345678-1234-1234-1234-123456789ABC") == true)
    }

    func testSigningDisabledIsUnavailableRatherThanReady() throws {
        let snapshot = try SigningStatusService.parse(
            output: fixture("build-settings-signing-disabled.json")
        )

        XCTAssertEqual(snapshot.overallStatus, .unavailable)
        XCTAssertEqual(snapshot.targets.first?.status, .unavailable)
    }

    func testMultipleTargetsPreserveStableOrderAndWarnForIncompleteConfiguration() throws {
        let snapshot = try SigningStatusService.parse(
            output: fixture("build-settings-signing-multiple.json")
        )

        XCTAssertEqual(snapshot.overallStatus, .warning)
        XCTAssertEqual(snapshot.targets.map(\.targetName), ["PosterApp", "PosterTests"])
        XCTAssertEqual(snapshot.targets[1].status, .warning)
    }

    func testMalformedJSONThrowsTypedSafeError() {
        XCTAssertThrowsError(try SigningStatusService.parse(output: fixture("build-settings-signing-malformed.json"))) { error in
            XCTAssertTrue(error is SigningStatusError)
            XCTAssertEqual(error.localizedDescription, "Xcode returned unrecognized signing build settings.")
        }
    }

    func testOversizedAndAbsoluteValuesAreBoundedOrOmitted() throws {
        let snapshot = try SigningStatusService.parse(
            output: """
            [{"target":"\(String(repeating: "T", count: 500))","buildSettings":{"PRODUCT_BUNDLE_IDENTIFIER":"\(String(repeating: "a", count: 500))","CODE_SIGN_STYLE":"Automatic","DEVELOPMENT_TEAM":"TEAM","CODE_SIGN_IDENTITY":"Apple Development","CODE_SIGNING_ALLOWED":"YES","CODE_SIGNING_REQUIRED":"YES","CODE_SIGN_ENTITLEMENTS":"/Users/example/private.entitlements","SDKROOT":"iphoneos"}}]
            """
        )

        let target = try XCTUnwrap(snapshot.targets.first)
        XCTAssertLessThanOrEqual(target.targetName.count, 128)
        XCTAssertLessThanOrEqual(target.bundleIdentifier?.count ?? 0, 256)
        XCTAssertNil(target.entitlements)
        XCTAssertFalse(String(describing: snapshot).contains("/Users/example"))
    }

    func testInspectionSpecificationUsesOnlySelectedReadOnlyBuildSettingsCommand() throws {
        let selection = BuildSelection(
            developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
            container: BuildContainer(
                kind: .project,
                path: "/repo/Poster.xcodeproj",
                label: "Poster.xcodeproj"
            ),
            scheme: "Poster",
            configuration: "Debug",
            destination: Destination(
                label: "My Mac",
                specifier: "platform=macOS",
                platform: "macOS",
                id: nil,
                generic: true
            )
        )

        let specification = try SigningStatusService().makeSpecification(
            selection: selection,
            workspaceRoot: "/repo"
        )

        XCTAssertEqual(specification.command, "/usr/bin/xcrun")
        XCTAssertEqual(specification.arguments, [
            "xcodebuild", "-project", "/repo/Poster.xcodeproj",
            "-scheme", "Poster", "-configuration", "Debug",
            "-destination", "platform=macOS", "-showBuildSettings", "-json"
        ])
        XCTAssertEqual(specification.environment, [
            "DEVELOPER_DIR": "/Applications/Xcode 27 rc.app/Contents/Developer"
        ])
        XCTAssertEqual(specification.workingDirectory, "/repo")
        XCTAssertFalse(specification.arguments.contains("-allowProvisioningUpdates"))
    }

    private func fixture(_ name: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try! String(
            contentsOf: root.appendingPathComponent("Tests/fixtures").appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
