//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SimulatorAnimations
import Testing

/// Covers the two pieces `swift-sure test` uses to switch animations off in the app under UI test: the `.xctestrun` copy that inserts the library, and the library's compile-once cache.
@Suite(.temporaryDirectories)
struct AnimationsOffTests {
    private static let original = URL(fileURLWithPath: "/Builds/Gizmo/Products", isDirectory: true)
    private static let library = URL(fileURLWithPath: "/Cache/animations-0123456789abcdef.dylib")

    /// The UI target's app gains the library, the unit target's dictionary does not, and no `__TESTROOT__` is left in strings at any depth.
    @Test
    func theUITargetsAppGainsTheLibraryAndNoTestRootIsLeft() throws {
        let plist: [String: Any] = [
            "__xctestrun_metadata__": ["format": 1],
            "GizmoApp": Self.target(isUITest: true, extra: ["DependentProductPaths": ["__TESTROOT__/Debug/Gizmo.app", ["__TESTROOT__/nested"]]]),
            "GizmoTests": Self.target(isUITest: false, extra: ["Host": "__TESTROOT__/Debug/Gizmo.app", "__PLATFORMS__": "kept"]),
        ]

        let rewritten = try #require(try AnimationsOffXCTestRun.rewritten(Self.xml(plist), originalDirectory: Self.original, library: Self.library))
        let root = try Self.decode(rewritten)

        let uiTarget = try #require(root["GizmoApp"] as? [String: Any])
        let unit = try #require(root["GizmoTests"] as? [String: Any])

        #expect((uiTarget["UITargetAppEnvironmentVariables"] as? [String: String])?["DYLD_INSERT_LIBRARIES"] == "/Cache/animations-0123456789abcdef.dylib")
        #expect((unit["UITargetAppEnvironmentVariables"] as? [String: String])?["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(unit["Host"] as? String == "/Builds/Gizmo/Products/Debug/Gizmo.app")
        #expect(unit["__PLATFORMS__"] as? String == "kept")
        #expect(uiTarget["DependentProductPaths"] as? NSArray == ["/Builds/Gizmo/Products/Debug/Gizmo.app", ["/Builds/Gizmo/Products/nested"]] as NSArray)
        #expect(String(bytes: rewritten, encoding: .utf8)?.contains("__TESTROOT__") == false)
    }

    /// A library the app environment already inserts stays, and the new one follows it after a colon.
    @Test
    func anExistingInsertedLibraryIsKeptWithTheNewOneAppended() throws {
        var uiTarget = Self.target(isUITest: true)
        uiTarget["UITargetAppEnvironmentVariables"] = ["DYLD_INSERT_LIBRARIES": "/Lib/Other.dylib", "GIZMO": "1"]

        let rewritten = try #require(try AnimationsOffXCTestRun.rewritten(Self.xml(["GizmoApp": uiTarget]), originalDirectory: Self.original, library: Self.library))
        let environment = try #require(try (Self.decode(rewritten)["GizmoApp"] as? [String: Any])?["UITargetAppEnvironmentVariables"] as? [String: String])

        #expect(environment["DYLD_INSERT_LIBRARIES"] == "/Lib/Other.dylib:/Cache/animations-0123456789abcdef.dylib")
        #expect(environment["GIZMO"] == "1")
    }

    /// A test-plan build, which nests its targets under `TestConfigurations`, is treated the same way.
    @Test
    func aTestPlanLayoutGetsTheSameTreatment() throws {
        let plist: [String: Any] = [
            "__xctestrun_metadata__": ["format": 2],
            "TestConfigurations": [
                [
                    "Name": "Default",
                    "TestTargets": [
                        Self.target(isUITest: false, extra: ["Host": "__TESTROOT__/Debug/Gizmo.app"]),
                        Self.target(isUITest: true, extra: ["DependentProductPaths": ["__TESTROOT__/Debug/GizmoApp.xctest"]]),
                    ],
                ],
            ],
        ]

        let rewritten = try #require(try AnimationsOffXCTestRun.rewritten(Self.xml(plist), originalDirectory: Self.original, library: Self.library))
        let configurations = try #require(try Self.decode(rewritten)["TestConfigurations"] as? [[String: Any]])
        let targets = try #require(configurations.first?["TestTargets"] as? [[String: Any]])

        #expect(targets.count == 2)
        #expect((targets[0]["UITargetAppEnvironmentVariables"] as? [String: String])?["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(targets[0]["Host"] as? String == "/Builds/Gizmo/Products/Debug/Gizmo.app")
        #expect((targets[1]["UITargetAppEnvironmentVariables"] as? [String: String])?["DYLD_INSERT_LIBRARIES"] == "/Cache/animations-0123456789abcdef.dylib")
        #expect(targets[1]["DependentProductPaths"] as? [String] == ["/Builds/Gizmo/Products/Debug/GizmoApp.xctest"])
    }

    /// With no UI target there is nothing to insert, so the original runs; a root that is not a dictionary is refused.
    @Test
    func noUITargetGivesNilAndANonDictionaryRootThrows() throws {
        let unitOnly: [String: Any] = ["GizmoTests": Self.target(isUITest: false)]
        #expect(try AnimationsOffXCTestRun.rewritten(Self.xml(unitOnly), originalDirectory: Self.original, library: Self.library) == nil)

        let array = try PropertyListSerialization.data(fromPropertyList: ["GizmoApp"], format: .xml, options: 0)
        #expect(throws: AnimationsOffError.self) {
            try AnimationsOffXCTestRun.rewritten(array, originalDirectory: Self.original, library: Self.library)
        }
    }

    /// A compile that fails throws SwiftSure's error with the compiler's first line only.
    @Test
    func aFailedCompileThrowsSiftsErrorWithTheStderrLine() throws {
        let directory = try TemporaryDirectory.make("animations-off")
        let library = try AnimationsOffLibrary.sift(environment: ["SWIFT_SURE_HOME": directory.path])

        let error = try #require(throws: AnimationsOffError.self) {
            try library.builtForSift { _, _ in
                Subprocess.Output(succeeded: false, standardOutput: "", standardError: "a.m:1:1: error: boom\nsecond line\n")
            }
        }

        #expect(error.description.contains("a.m:1:1: error: boom"))
        #expect(error.description.contains("second line") == false)
    }

    /// The default directory is `libraries` under SwiftSure's home, which `SWIFT_SURE_HOME` moves.
    @Test
    func theDefaultDirectoryIsLibrariesUnderSiftHome() throws {
        #expect(try AnimationsOffLibrary.sift(environment: ["SWIFT_SURE_HOME": "/Probe/home"]).directory.path == "/Probe/home/libraries")
    }

    /// The library reads `SWIFT_SURE_ANIMATIONS` and sets `SWIFT_SURE_ANIMATIONS_LOADED`, the two names the Guide documents.
    @Test
    func theLibraryReadsAndSetsTheDocumentedVariables() throws {
        let source = try AnimationsOffLibrary.sift(environment: ["SWIFT_SURE_HOME": "/Probe/home"]).source

        #expect(source.contains(#"getenv("SWIFT_SURE_ANIMATIONS")"#))
        #expect(source.contains(#"setenv("SWIFT_SURE_ANIMATIONS_LOADED", "1", 1)"#))
    }

    /// The copy is written as `<directory>/<original file name>` and holds the path the build step returned.
    @Test
    func theLiveSeamWritesTheCopyUnderTheOriginalNameWithTheLibraryPath() throws {
        let root = try TemporaryDirectory.make("animations-off")
        let original = root.appendingPathComponent("Gizmo.xctestrun")
        try Self.xml(["GizmoApp": Self.target(isUITest: true)]).write(to: original)
        let directory = root.appendingPathComponent("ledger", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let copy = try #require(try TestRunEnvironment.liveXCTestRunWithAnimationsOff(original: original, directory: directory) { Self.library })

        #expect(copy == directory.appendingPathComponent("Gizmo.xctestrun"))
        let target = try #require(try Self.decode(Data(contentsOf: copy))["GizmoApp"] as? [String: Any])
        #expect((target["UITargetAppEnvironmentVariables"] as? [String: String])?["DYLD_INSERT_LIBRARIES"] == Self.library.path)
    }

    /// A plist with no UI target returns nil and never asks for the library to be built.
    @Test
    func theLiveSeamNeverBuildsWhenThereIsNoUITarget() throws {
        let root = try TemporaryDirectory.make("animations-off")
        let original = root.appendingPathComponent("Gizmo.xctestrun")
        try Self.xml(["GizmoTests": Self.target(isUITest: false)]).write(to: original)
        var built = false

        let copy = try TestRunEnvironment.liveXCTestRunWithAnimationsOff(original: original, directory: root) {
            built = true
            return Self.library
        }

        #expect(copy == nil)
        #expect(built == false)
    }

    /// A build that fails throws, and no copy is written.
    @Test
    func theLiveSeamThrowsAndWritesNothingWhenTheBuildFails() throws {
        let root = try TemporaryDirectory.make("animations-off")
        let original = root.appendingPathComponent("Gizmo.xctestrun")
        try Self.xml(["GizmoApp": Self.target(isUITest: true)]).write(to: original)
        let directory = root.appendingPathComponent("ledger", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        #expect(throws: AnimationsOffError.self) {
            try TestRunEnvironment.liveXCTestRunWithAnimationsOff(original: original, directory: directory) {
                throw AnimationsOffError.libraryNotBuilt("boom")
            }
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private static func target(isUITest: Bool, extra: [String: Any] = [:]) -> [String: Any] {
        var target: [String: Any] = ["IsUITestBundle": isUITest, "BlueprintName": isUITest ? "GizmoApp" : "GizmoTests"]
        for (key, value) in extra {
            target[key] = value
        }
        return target
    }

    private static func xml(_ plist: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private static func decode(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], sourceLocation: sourceLocation)
    }
}
