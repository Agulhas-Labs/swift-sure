//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import SimulatorServices
import Testing

/// Covers the declarations read from build settings and the slim-or-stock decision, over fixture settings and a fixture profile.
@Suite(.temporaryDirectories)
struct SlimBootTests {
    private static var application: String {
        "com.apple.product-type.application"
    }

    // MARK: - Reading the settings

    /// A framework's entitlements are not the app's, so only the application target's keys are read.
    @Test
    func onlyApplicationTargetsAreRead() throws {
        let root = try TemporaryDirectory.make("slim-boot")
        try Self.writePlist(["com.apple.developer.healthkit": true], to: root, named: "Gizmo.entitlements")
        try Self.writePlist(["aps-environment": "development"], to: root, named: "GizmoKit.entitlements")
        let data = try Self.settings([
            ["PRODUCT_TYPE": Self.application, "SRCROOT": root.path, "CODE_SIGN_ENTITLEMENTS": "Gizmo.entitlements"],
            ["PRODUCT_TYPE": "com.apple.product-type.framework", "SRCROOT": root.path, "CODE_SIGN_ENTITLEMENTS": "GizmoKit.entitlements"],
        ])

        let found = try Self.read(data)

        #expect(found.entitlements == ["com.apple.developer.healthkit"])
    }

    /// No application target is a readable project that declares nothing.
    @Test
    func noApplicationTargetDeclaresNothing() throws {
        let data = try Self.settings([["PRODUCT_TYPE": "com.apple.product-type.framework"]])

        #expect(try Self.read(data) == ProjectDeclarations())
    }

    /// A relative path resolves against that target's `SRCROOT`, and an absolute one is kept as written.
    @Test
    func relativeAndAbsolutePathsResolve() throws {
        let root = try TemporaryDirectory.make("slim-boot")
        let elsewhere = try TemporaryDirectory.make("slim-boot")
        try Self.writePlist(["com.apple.developer.healthkit": true], to: root, named: "Gizmo/Gizmo.entitlements", subdirectory: true)
        try Self.writePlist(["NSHealthShareUsageDescription": "Gizmo reads health."], to: elsewhere, named: "Info.plist")
        let data = try Self.settings([[
            "PRODUCT_TYPE": Self.application,
            "SRCROOT": root.path,
            "CODE_SIGN_ENTITLEMENTS": "Gizmo/Gizmo.entitlements",
            "INFOPLIST_FILE": elsewhere.appendingPathComponent("Info.plist").path,
        ]])

        let found = try Self.read(data)

        #expect(found.entitlements == ["com.apple.developer.healthkit"])
        #expect(found.infoPlistKeys == ["NSHealthShareUsageDescription"])
    }

    /// The generated Info.plist's keys come from the `INFOPLIST_KEY_` settings.
    @Test
    func generatedInfoPlistKeysAreRead() throws {
        let data = try Self.settings([[
            "PRODUCT_TYPE": Self.application,
            "INFOPLIST_KEY_NSCameraUsageDescription": "Gizmo scans.",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        ]])

        let found = try Self.read(data)

        #expect(found.infoPlistKeys == ["NSCameraUsageDescription", "UILaunchScreen_Generation"])
    }

    /// `UIBackgroundModes` values in the Info.plist are read, across targets.
    @Test
    func backgroundModesAreRead() throws {
        let root = try TemporaryDirectory.make("slim-boot")
        try Self.writePlist(["UIBackgroundModes": ["audio", "fetch"]], to: root, named: "Info.plist")
        let data = try Self.settings([["PRODUCT_TYPE": Self.application, "SRCROOT": root.path, "INFOPLIST_FILE": "Info.plist"]])

        let found = try Self.read(data)

        #expect(found.backgroundModes == ["audio", "fetch"])
    }

    /// A named entitlements file that is missing makes the read unreadable, naming the path as it was written.
    @Test
    func aMissingEntitlementsFileIsUnreadable() throws {
        let root = try TemporaryDirectory.make("slim-boot")
        let data = try Self.settings([["PRODUCT_TYPE": Self.application, "SRCROOT": root.path, "CODE_SIGN_ENTITLEMENTS": "Gizmo/Gizmo.entitlements"]])

        let result = ProjectSettings.declarations(inBuildSettings: data, schemeFiles: [])

        #expect(result == .failure(UnreadableDeclarations("Gizmo/Gizmo.entitlements: no such file")))
    }

    /// A file that is there but is not a property list is unreadable too.
    @Test
    func anUnparseableFileIsUnreadable() throws {
        let root = try TemporaryDirectory.make("slim-boot")
        try Data("not a plist".utf8).write(to: root.appendingPathComponent("Gizmo.entitlements"))
        let data = try Self.settings([["PRODUCT_TYPE": Self.application, "SRCROOT": root.path, "CODE_SIGN_ENTITLEMENTS": "Gizmo.entitlements"]])

        let result = ProjectSettings.declarations(inBuildSettings: data, schemeFiles: [])

        guard case let .failure(failure) = result else {
            Issue.record("expected unreadable, got \(result)")
            return
        }

        #expect(failure.reason.hasPrefix("Gizmo.entitlements: "))
    }

    /// JSON that does not decode is unreadable.
    @Test
    func undecodableJSONIsUnreadable() {
        let result = ProjectSettings.declarations(inBuildSettings: Data("{}".utf8), schemeFiles: [])

        guard case let .failure(failure) = result else {
            Issue.record("expected unreadable, got \(result)")
            return
        }

        #expect(failure.reason.hasPrefix("build settings did not decode"))
    }

    /// StoreKit is declared when a scheme file holds a configuration reference, and a scheme file that is absent declares nothing.
    @Test
    func storeKitComesFromTheSchemeFile() throws {
        let root = try TemporaryDirectory.make("slim-boot")
        let withReference = root.appendingPathComponent("With.xcscheme")
        let without = root.appendingPathComponent("Without.xcscheme")
        try Data("<StoreKitConfigurationFileReference identifier=\"../Gizmo.storekit\"/>".utf8).write(to: withReference)
        try Data("<Scheme/>".utf8).write(to: without)
        let data = try Self.settings([["PRODUCT_TYPE": Self.application]])

        #expect(try Self.read(data, schemeFiles: [without, withReference]).storeKitConfiguration)
        #expect(try Self.read(data, schemeFiles: [without]).storeKitConfiguration == false)
        #expect(try Self.read(data, schemeFiles: [root.appendingPathComponent("Missing.xcscheme")]).storeKitConfiguration == false)
    }

    /// The scheme files are the container's shared scheme and each application target's project's, once each.
    @Test
    func schemeFilesAreNamedFromTheContainerAndTheTargets() throws {
        let data = try Self.settings([
            ["PRODUCT_TYPE": Self.application, "PROJECT_FILE_PATH": "/work/Gizmo.xcodeproj"],
            ["PRODUCT_TYPE": "com.apple.product-type.framework", "PROJECT_FILE_PATH": "/work/Other.xcodeproj"],
        ])

        let files = ProjectSettings.schemeFiles(container: .workspace("/work/Gizmo.xcworkspace"), scheme: "Gizmo", inBuildSettings: data)

        #expect(files.map(\.path) == [
            "/work/Gizmo.xcworkspace/xcshareddata/xcschemes/Gizmo.xcscheme",
            "/work/Gizmo.xcodeproj/xcshareddata/xcschemes/Gizmo.xcscheme",
        ])
    }

    // MARK: - The decision

    /// `--stock` decides before anything is looked up, and the declarations are never read.
    @Test
    func stockRequestedNeverReadsTheDeclarations() {
        var read = false
        let mode = BootMode.decide(
            stockRequested: true, runtimeIdentifier: Self.runtime, osVersion: "27.0",
            profileLookup: { _ in Self.profile },
            declarations: {
                read = true
                return .success(ProjectDeclarations())
            }
        )

        #expect(mode == .stock(.requested))
        #expect(read == false)
    }

    /// A runtime with no profile boots stock, and says which version had none.
    @Test
    func noProfileIsStock() {
        let mode = Self.decide(profile: nil, declarations: .success(ProjectDeclarations()), osVersion: "26.4")

        #expect(mode == .stock(.noProfile(osVersion: "26.4")))
    }

    /// Declarations that could not be read boot stock with the reason.
    @Test
    func unreadableDeclarationsAreStock() {
        let mode = Self.decide(profile: Self.profile, declarations: .failure(UnreadableDeclarations("Gizmo/Gizmo.entitlements: no such file")))

        #expect(mode == .stock(.unreadable("Gizmo/Gizmo.entitlements: no such file")))
    }

    /// A declaration no rule accounts for boots stock and is named.
    @Test
    func unmappedDeclarationsAreStock() {
        let declarations = ProjectDeclarations(infoPlistKeys: ["NSLocationWhenInUseUsageDescription"], backgroundModes: ["audio"])

        let mode = Self.decide(profile: Self.profile, declarations: .success(declarations))

        #expect(mode == .stock(.unmapped(["NSLocationWhenInUseUsageDescription", "UIBackgroundModes:audio"])))
    }

    /// Everything accounted for is slim, keeping the services the project's capabilities need.
    @Test
    func accountedForDeclarationsAreSlim() {
        let declarations = ProjectDeclarations(entitlements: ["com.apple.developer.healthkit"])

        let mode = Self.decide(profile: Self.profile, declarations: .success(declarations))

        guard case let .slim(boot) = mode else {
            Issue.record("expected slim, got \(mode)")
            return
        }

        #expect(boot.plan.disabled == ["com.gizmo.c"])
        #expect(boot.plan.kept == [.healthKit: ["com.gizmo.a", "com.gizmo.b"]])
    }

    // MARK: - The words

    /// Each stock reason prints exactly as the design quotes it.
    @Test
    func stockTextsAreExact() {
        #expect(StockReason.requested.text == "--stock")
        #expect(StockReason.noProfile(osVersion: "26.4").text == "no service profile for iOS 26.4")
        #expect(StockReason.unreadable("Gizmo/Gizmo.entitlements: no such file").text
            == "the project's declarations could not be read (Gizmo/Gizmo.entitlements: no such file)")
        #expect(StockReason.unmapped(["NSLocationWhenInUseUsageDescription", "UIBackgroundModes:audio"]).text
            == "the project declares what no rule maps (NSLocationWhenInUseUsageDescription, UIBackgroundModes:audio)")
        #expect(BootMode.stock(.requested).text == "stock: --stock")
    }

    /// The slim text counts the services off of those the profile lists, and names each kept capability with its count.
    @Test
    func slimTextIsExact() {
        let kept = Self.decide(profile: Self.profile, declarations: .success(ProjectDeclarations(entitlements: ["com.apple.developer.healthkit"])))
        let nothing = Self.decide(profile: Self.profile, declarations: .success(ProjectDeclarations()))

        #expect(kept.text == "slim: 1 of 4 services off (iOS 27.0, profile v1), kept for the project: healthKit 2")
        #expect(nothing.text == "slim: 3 of 4 services off (iOS 27.0, profile v1), kept for the project: nothing")
    }

    // MARK: - Fixtures

    private static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    /// Four services: three the profile disables and one the runtime needs, two of the disabled serving HealthKit.
    private static let profile: ServiceProfile = {
        func entry(_ label: String, _ disposition: Disposition) -> ServiceEntry {
            ServiceEntry(label: label, domain: .daemon, start: .onDemand, ranAtBoot: true, peakFootprintMB: nil, cpuSeconds: nil, disposition: disposition)
        }
        return ServiceProfile(
            profileVersion: 1,
            runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A000"),
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            generated: "2026-10-01",
            method: ProfileMethod(costWindowSeconds: 60, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
            services: [entry("com.gizmo.a", .disable), entry("com.gizmo.b", .disable), entry("com.gizmo.c", .disable), entry("com.gizmo.core", .core)],
            capabilities: [.healthKit: ["com.gizmo.a", "com.gizmo.b"]]
        )
    }()

    private static func decide(
        profile: ServiceProfile?,
        declarations: Result<ProjectDeclarations, UnreadableDeclarations>,
        osVersion: String = "27.0"
    ) -> BootMode {
        BootMode.decide(
            stockRequested: false, runtimeIdentifier: runtime, osVersion: osVersion,
            profileLookup: { _ in profile }, declarations: { declarations }
        )
    }

    private static func read(_ data: Data, schemeFiles: [URL] = []) throws -> ProjectDeclarations {
        try ProjectSettings.declarations(inBuildSettings: data, schemeFiles: schemeFiles).get()
    }

    private static func settings(_ targets: [[String: String]]) throws -> Data {
        let entries = targets.enumerated().map { ["target": "Target\($0.offset)", "buildSettings": $0.element] }
        return try JSONSerialization.data(withJSONObject: entries)
    }

    private static func writePlist(_ contents: [String: Any], to directory: URL, named name: String, subdirectory: Bool = false) throws {
        let url = directory.appendingPathComponent(name)
        if subdirectory {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0).write(to: url)
    }
}
