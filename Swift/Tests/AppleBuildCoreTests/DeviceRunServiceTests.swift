import Foundation
import XCTest
@testable import AppleBuildCore

final class DeviceRunServiceTests: XCTestCase {
    private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
    private let deviceID = "00000000-0000000000000000"

    func testPreparesFixedInstallAndLaunchCommandsForConnectedIPhone() async throws {
        let runner = RecordingProcessRunner(output: appBuildSettings)
        let service = DeviceRunService(processRunner: runner)

        let plan = try await service.prepare(selection: selection(destination: iPhone), workspaceRoot: "/repo")

        XCTAssertEqual(runner.specifications.count, 1)
        XCTAssertEqual(runner.specifications.first?.arguments, [
            "xcodebuild", "-project", "/repo/Poster.xcodeproj",
            "-scheme", "Poster", "-configuration", "Debug",
            "-destination", "platform=iOS,id=\(deviceID)", "-showBuildSettings", "-json"
        ])
        XCTAssertEqual(plan.appName, "PosterApp.app")
        XCTAssertEqual(plan.kind, "iphone")
        XCTAssertEqual(plan.steps, [])
        XCTAssertNil(plan.activate)
        XCTAssertEqual(plan.readyPattern, #"^Launched application\b"#)
        XCTAssertEqual(plan.bundleIdentifier, "com.example.poster")
        XCTAssertEqual(plan.deviceName, "Sam’s iPhone")
        XCTAssertEqual(plan.install, ProcessSpecification(
            command: "/usr/bin/xcrun",
            arguments: [
                "devicectl", "device", "install", "app",
                "--device", deviceID,
                "/tmp/DerivedData/Build/Products/Debug-iphoneos/PosterApp.app"
            ],
            environment: ["DEVELOPER_DIR": developerDirectory],
            workingDirectory: "/repo"
        ))
        XCTAssertEqual(plan.launch, ProcessSpecification(
            command: "/usr/bin/xcrun",
            arguments: [
                "devicectl", "device", "process", "launch",
                "--device", deviceID, "--terminate-existing", "--console", "com.example.poster"
            ],
            environment: ["DEVELOPER_DIR": developerDirectory],
            workingDirectory: "/repo"
        ))
    }

    func testInspectReportsAppNameWithoutExtension() async throws {
        let service = DeviceRunService(processRunner: RecordingProcessRunner(output: appBuildSettings))
        let product = try await service.inspect(selection: selection(destination: iPhone), workspaceRoot: "/repo")
        XCTAssertEqual(product.appName, "PosterApp")
        XCTAssertEqual(product.deviceID, deviceID)
        XCTAssertEqual(product.deviceName, "Sam’s iPhone")
    }

    func testRejectsDeviceIdentifierThatLooksLikeAnOption() async {
        let destination = Destination(
            label: "Odd", specifier: "platform=iOS,id=--json", platform: "iOS", id: "--json", generic: false
        )
        let service = DeviceRunService(processRunner: RecordingProcessRunner(output: appBuildSettings))
        do {
            _ = try await service.prepare(selection: selection(destination: destination), workspaceRoot: "/repo")
            XCTFail("Expected rejection.")
        } catch {
            XCTAssertTrue(error is DeviceRunError)
        }
    }

    func testParseChoosesTheApplicationTargetAndIgnoresTestBundles() throws {
        let product = try DeviceRunService.parseProduct(output: """
        [
          {"target":"PosterTests","buildSettings":{"WRAPPER_EXTENSION":"xctest","TARGET_BUILD_DIR":"/tmp/p","WRAPPER_NAME":"PosterTests.xctest","PRODUCT_BUNDLE_IDENTIFIER":"app.tests"}},
          {"target":"PosterApp","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp/p","WRAPPER_NAME":"PosterApp.app","PRODUCT_BUNDLE_IDENTIFIER":"app.poster"}}
        ]
        """)

        XCTAssertEqual(product.appPath, "/tmp/p/PosterApp.app")
        XCTAssertEqual(product.bundleIdentifier, "app.poster")
    }

    func testParseFailsSafelyWithoutAnInstallableApp() {
        let outputs = [
            "not json",
            "[]",
            #"[{"target":"Lib","buildSettings":{"WRAPPER_EXTENSION":"framework","TARGET_BUILD_DIR":"/tmp","WRAPPER_NAME":"Lib.framework","PRODUCT_BUNDLE_IDENTIFIER":"lib"}}]"#,
            #"[{"target":"App","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"relative","WRAPPER_NAME":"App.app","PRODUCT_BUNDLE_IDENTIFIER":"app"}}]"#,
            #"[{"target":"App","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp","WRAPPER_NAME":"App.app"}}]"#,
            #"[{"target":"App","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp","WRAPPER_NAME":"../App.app","PRODUCT_BUNDLE_IDENTIFIER":"app"}}]"#
        ]
        for output in outputs {
            XCTAssertThrowsError(try DeviceRunService.parseProduct(output: output), output) { error in
                XCTAssertTrue(error is DeviceRunError)
            }
        }
    }

    func testFailedBuildSettingsInspectionIsReadable() async {
        let service = DeviceRunService(processRunner: RecordingProcessRunner(output: "", status: 65))
        do {
            _ = try await service.prepare(selection: selection(destination: iPhone), workspaceRoot: "/repo")
            XCTFail("Expected failure.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Xcode could not report where it built the app for this iPhone."
            )
        }
    }

    private var iPhone: Destination {
        Destination(
            label: "Sam’s iPhone — iOS, arm64e, \(deviceID)",
            specifier: "platform=iOS,id=\(deviceID)",
            platform: "iOS",
            id: deviceID,
            generic: false
        )
    }

    private var appBuildSettings: String {
        """
        [{"target":"PosterApp","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp/DerivedData/Build/Products/Debug-iphoneos","WRAPPER_NAME":"PosterApp.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.poster","UNRELATED":"value"}}]
        """
    }

    private func selection(destination: Destination) -> BuildSelection {
        BuildSelection(
            developerDirectory: developerDirectory,
            container: BuildContainer(kind: .project, path: "/repo/Poster.xcodeproj", label: "Poster.xcodeproj"),
            scheme: "Poster",
            configuration: "Debug",
            destination: destination
        )
    }
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    private let output: String
    private let status: Int32
    private let lock = NSLock()
    private var recorded: [ProcessSpecification] = []

    init(output: String, status: Int32 = 0) {
        self.output = output
        self.status = status
    }

    var specifications: [ProcessSpecification] {
        lock.withLock { recorded }
    }

    func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        lock.withLock { recorded.append(specification) }
        return ProcessResult(status: status, standardOutput: output, standardError: "")
    }
}
