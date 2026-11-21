//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the written-name walk on a `private` or `fileprivate` declaration: no other file can spell it, so a same-named site elsewhere is never a use of it.
@Suite(.serialized, .temporaryDirectories)
struct AffectedFileLocalNameTests {
    private static var manifest: String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Lib",
            targets: [
                .target(name: "Lib"),
                .testTarget(name: "LibTests", dependencies: ["Lib"]),
            ]
        )
        """
    }

    private static func suite(_ name: String, body: String, helpers: String = "") -> String {
        "import Testing\n@testable import Lib\n\nstruct \(name) {\n\(helpers)    @Test func runs() {\n        \(body)\n    }\n}\n"
    }

    private static func gizmo(step: String, overload: Bool) -> String {
        let wider = overload ? "    public static func run(count: Int) -> Int {\n        count + run()\n    }\n\n" : ""
        return "public enum Gizmo {\n    public static func tally() -> Int {\n        run()\n    }\n\n\(wider)    private static func run() -> Int {\n        \(step)\n    }\n}\n"
    }

    private static func scriptTests(returning value: String) -> String {
        suite("ConveyorBeltTests", body: "#expect(Self.run() == \(value))", helpers: "    private static func run() -> Int {\n        \(value)\n    }\n\n")
    }

    /// An engine over a fixture with no build, where `Gizmo`'s private `run()` or `ConveyorBeltTests`'s private `run()` is changed and uncommitted.
    ///
    /// `KettleTests` calls `Gizmo.tally()`, `LampTests` calls an unrelated `Lamp().run()`, and `DepotTests` calls `Gizmo.run(count:)`, a public overload declared when `overload` is set.
    private static func engine(editing path: String, overload: Bool = false) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        let files = [
            "Package.swift": manifest,
            "Sources/Lib/Gizmo.swift": gizmo(step: "1", overload: overload),
            "Sources/Lib/Lamp.swift": "public struct Lamp {\n    public init() {}\n    public func run() -> Int {\n        2\n    }\n}\n",
            "Tests/LibTests/KettleTests.swift": suite("KettleTests", body: "_ = Gizmo.tally()"),
            "Tests/LibTests/DepotTests.swift": suite("DepotTests", body: "_ = Gizmo.run(count: 2)"),
            "Tests/LibTests/LampTests.swift": suite("LampTests", body: "_ = Lamp().run()"),
            "Tests/LibTests/ConveyorBeltTests.swift": scriptTests(returning: "3"),
        ]
        for (file, source) in files {
            try TestSources.write(source, to: file, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        let edited = path.hasPrefix("Sources") ? gizmo(step: "1 + 1", overload: overload) : scriptTests(returning: "4")
        try TestSources.write(edited, to: path, in: root)
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return engine
    }

    /// The `filtered:` line's walk from an edited test file reaches that file's own suite and not every suite writing its private helper's name.
    @Test
    func anEditedTestFilesPrivateHelperReachesOnlyItsOwnSuite() async throws {
        let engine = try await Self.engine(editing: "Tests/LibTests/ConveyorBeltTests.swift")

        let reached = try #require(try await engine.suitesReachingWorkingTree()).suites.map(\.filter)

        #expect(reached.contains("LibTests.ConveyorBeltTests"), "\(reached)")
        #expect(!reached.contains("LibTests.LampTests"), "\(reached)")
    }

    /// `affected` on an edited private helper reaches the suite calling the public function that uses it, not one calling another type's same-named method.
    @Test
    func aChangedPrivateHelperIsNotMatchedInAnotherFile() async throws {
        let engine = try await Self.engine(editing: "Sources/Lib/Gizmo.swift")

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.KettleTests/runs()"), "\(output)")
        #expect(!output.contains("LampTests"), "\(output)")
    }

    /// A name first scanned only in a private declaration's file is scanned across the tree once the walk reaches a wider declaration of it, so the suite calling the public overload is still reached.
    @Test
    func aWiderDeclarationOfTheSameNameIsScannedEverywhere() async throws {
        let engine = try await Self.engine(editing: "Sources/Lib/Gizmo.swift", overload: true)

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.DepotTests/runs()"), "\(output)")
    }

    /// An engine over `files` with no build, committed, then `path` rewritten to `edited` and left uncommitted.
    private static func engine(files: [String: String], editing path: String, to edited: String) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        for (file, source) in files.merging(["Package.swift": manifest], uniquingKeysWith: { _, new in new }) {
            try TestSources.write(source, to: file, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write(edited, to: path, in: root)
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return engine
    }

    private static func belt(_ value: String) -> String {
        suite("ConveyorBeltTests", body: "#expect(Belt().width == \(value))", helpers: "    struct Belt {\n        let width = 3\n    }\n\n")
    }

    private static func xcBase(_ value: String) -> String {
        "import XCTest\n\nclass AlphaTests: XCTestCase {\n    func testBuckles() {\n        XCTAssertEqual(\(value), 1)\n    }\n}\n"
    }

    /// A type nested in an edited test file's suite still leads on to the suite that builds it.
    @Test
    func anEditedSuitesNestedTypeReachesTheSuiteBuildingIt() async throws {
        let files = ["Tests/LibTests/ConveyorBeltTests.swift": Self.belt("3"), "Tests/LibTests/DialTests.swift": Self.suite("DialTests", body: "_ = ConveyorBeltTests.Belt()")]
        let engine = try await Self.engine(files: files, editing: "Tests/LibTests/ConveyorBeltTests.swift", to: Self.belt("4"))

        let reached = try #require(try await engine.suitesReachingWorkingTree()).suites.map(\.filter)

        #expect(reached.contains("LibTests.DialTests"), "\(reached)")
    }

    /// An edited XCTest base class still leads on to the subclass that inherits its tests.
    @Test
    func anEditedBaseSuiteReachesItsSubclass() async throws {
        let files = ["Tests/LibTests/AlphaTests.swift": Self.xcBase("1"), "Tests/LibTests/BetaTests.swift": "import XCTest\n\nfinal class BetaTests: AlphaTests {}\n"]
        let engine = try await Self.engine(files: files, editing: "Tests/LibTests/AlphaTests.swift", to: Self.xcBase("2 - 1"))

        let reached = try #require(try await engine.suitesReachingWorkingTree()).suites.map(\.filter)

        #expect(reached.contains("LibTests.BetaTests"), "\(reached)")
    }

    /// A `fileprivate` member of a conforming type may witness a requirement called through the protocol in another file, so its name is not confined.
    @Test
    func aFilePrivateWitnessIsMatchedWhereTheProtocolCallsIt() async throws {
        func fast(_ value: String) -> String {
            "public protocol Spinner {\n    func whirl() -> Int\n}\n\nprivate struct Fast: Spinner {\n    fileprivate func whirl() -> Int {\n        \(value)\n    }\n}\n"
        }
        let files = ["Sources/Lib/Fast.swift": fast("1"), "Tests/LibTests/DialTests.swift": Self.suite("DialTests", body: "_ = (nil as (any Spinner)?)?.whirl()")]
        let engine = try await Self.engine(files: files, editing: "Sources/Lib/Fast.swift", to: fast("2"))

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.DialTests/runs()"), "\(output)")
    }

    /// A `fileprivate` member a subclass inherits, or a protocol extension's `fileprivate` default, may witness a requirement too, so neither is confined.
    @Test(arguments: [
        "private class Base {\n    fileprivate func whirl() -> Int {\n        VALUE\n    }\n}\n\nprivate final class Fast: Base {}\n\nextension Fast: Spinner {}\n",
        "extension Spinner {\n    fileprivate func whirl() -> Int {\n        VALUE\n    }\n}\n\nprivate struct Fast: Spinner {}\n",
    ])
    func aWitnessDeclaredOffTheConformingTypeIsNotConfined(_ shape: String) async throws {
        let spinner = "public protocol Spinner {\n    func whirl() -> Int\n}\n"
        let files = ["Sources/Lib/Spinner.swift": spinner, "Sources/Lib/Fast.swift": shape.replacingOccurrences(of: "VALUE", with: "1"), "Tests/LibTests/DialTests.swift": Self.suite("DialTests", body: "_ = (nil as (any Spinner)?)?.whirl()")]
        let engine = try await Self.engine(files: files, editing: "Sources/Lib/Fast.swift", to: shape.replacingOccurrences(of: "VALUE", with: "2"))

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.DialTests/runs()"), "\(output)")
    }

    /// A declaration the diff made private still has its callers in other files matched, since they spell it until they are changed.
    @Test
    func aDeclarationTheDiffMadePrivateKeepsItsCallersElsewhere() async throws {
        func dial(_ access: String) -> String {
            "public enum Dial {\n    \(access) static func spin() -> Int {\n        1\n    }\n}\n"
        }
        let files = ["Sources/Lib/Dial.swift": dial("public"), "Tests/LibTests/DialTests.swift": Self.suite("DialTests", body: "_ = Dial.spin()")]
        let engine = try await Self.engine(files: files, editing: "Sources/Lib/Dial.swift", to: dial("private"))

        let output = try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())

        #expect(output.contains("LibTests.DialTests/runs()"), "\(output)")
    }
}
