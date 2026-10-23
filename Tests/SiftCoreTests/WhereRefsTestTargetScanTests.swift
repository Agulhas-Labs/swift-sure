//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Under `--refs`, where the store holds no unit for a test target's files, every Swift file of that target is searched by written name: the answer lists the lines that write the name, or says that none does, in place of advice to build the tests.
///
/// An answer that only said the tests were not built left a reader asked to count tests too nothing to do but grep for the name.
@Suite(.temporaryDirectories, .serialized)
struct WhereRefsTestTargetScanTests {
    /// A package built without its tests: `loadAlpha` has two production callers and no test file writes it, `loadGamma` has none, `loadBeta` is called from a test helper that imports no test framework, and the test target holds an Objective-C file the build leaves out.
    private static func neverBuiltFixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "where-refs-test-target-never-built") { root in
            try Self.writePackage(in: root)
            try await TestSources.swiftBuildSuspending(packageAt: root)
        }
    }

    /// The same package built with its tests.
    private static func testsBuiltFixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "where-refs-test-target-built") { root in
            try Self.writePackage(in: root)
            try await TestSources.swiftBuildSuspending(packageAt: root, includingTests: true)
        }
    }

    private static func writePackage(in root: URL) throws {
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Lib",
                targets: [
                    .target(name: "Lib"),
                    .testTarget(name: "LibTests", dependencies: ["Lib"], exclude: ["Legacy.m"]),
                ]
            )
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write("public func loadAlpha() {}\n\npublic func loadBeta() {}\n\npublic func loadGamma() {}\n", to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write("public func start() {\n    loadAlpha()\n    loadBeta()\n}\n", to: "Sources/Lib/Start.swift", in: root)
        try TestSources.write("public func restart() {\n    loadAlpha()\n}\n", to: "Sources/Lib/Restart.swift", in: root)
        try TestSources.write("@testable import Lib\nimport Testing\n\n@Test func starts() {\n    start()\n}\n", to: "Tests/LibTests/GizmoTests.swift", in: root)
        try TestSources.write("@testable import Lib\n\nfunc prepare() {\n    loadBeta()\n}\n", to: "Tests/LibTests/GizmoTools.swift", in: root)
        try TestSources.write("#import <Foundation/Foundation.h>\n", to: "Tests/LibTests/Legacy.m", in: root)
        try TestSources.commitAll(in: root, message: "test target scan fixture")
    }

    private static func refs(of symbol: String, in fixture: SharedBuiltFixture) async throws -> String {
        try await fixture.withEngine { engine in
            try await engine.lookup(symbol: symbol, freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))
        }
    }

    /// The motivating case: both production callers listed, and the never-built test target searched by name and found not to write it, with no advice to build the tests.
    @Test
    func aNeverBuiltTestTargetNotWritingTheNameSaysSoInsteadOfAdvisingABuild() async throws {
        let output = try await Self.refs(of: "loadAlpha", in: Self.neverBuiltFixture())

        #expect(output.contains("Sources/Lib/Start.swift"), "\(output)")
        #expect(output.contains("Sources/Lib/Restart.swift"), "\(output)")
        #expect(output.contains("none of the 2 Swift files in test targets writes the name"), "\(output)")
        #expect(!output.contains("build the test target"), "\(output)")
        #expect(!output.contains("swift build --build-tests"), "\(output)")
    }

    /// A test helper importing no test framework is a file of the test target, so its call is listed by file and line.
    @Test
    func aTestHelperWritingTheNameIsListedByLine() async throws {
        let output = try await Self.refs(of: "loadBeta", in: Self.neverBuiltFixture())

        #expect(output.contains("not in the build, mention the name: Tests/LibTests/GizmoTools.swift:4"), "\(output)")
        #expect(!output.contains("none of the 2 Swift files in test targets"), "\(output)")
    }

    /// The Objective-C file in the test target is declared as not read.
    @Test
    func anObjectiveCTestFileIsCountedAsNotRead() async throws {
        let output = try await Self.refs(of: "loadAlpha", in: Self.neverBuiltFixture())

        #expect(output.contains("none of the 2 Swift files in test targets writes the name; 1 Objective-C test file not read"), "\(output)")
    }

    /// An empty verdict carries the result where it carried the advice to build the tests.
    @Test
    func anEmptyVerdictCarriesTheResultInPlaceOfTheBuildAdvice() async throws {
        let output = try await Self.refs(of: "loadGamma", in: Self.neverBuiltFixture())

        #expect(output.contains("no callers of Lib.loadGamma() recorded in the store; none of the 2 Swift files in test targets writes the name; 1 Objective-C test file not read"), "\(output)")
        #expect(!output.contains("not in it"), "\(output)")
    }

    /// With the tests built the store's answer is complete: nothing is searched by name and nothing is added.
    @Test
    func aBuiltTestTargetAddsNothing() async throws {
        let output = try await Self.refs(of: "loadAlpha", in: Self.testsBuiltFixture())

        #expect(output.contains("Sources/Lib/Restart.swift"), "\(output)")
        #expect(!output.contains("Swift files in test targets"), "\(output)")
        #expect(!output.contains("Objective-C"), "\(output)")
    }

    /// A package built without its tests, whose `Gizmo` type has production uses and is written by no test file.
    private static func typeFixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "where-refs-test-target-type-never-built") { root in
            try TestSources.write(
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
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("public struct Gizmo {\n    public init() {}\n}\n", to: "Sources/Lib/Gizmo.swift", in: root)
            try TestSources.write("public func start() -> Gizmo {\n    Gizmo()\n}\n", to: "Sources/Lib/Start.swift", in: root)
            try TestSources.write("@testable import Lib\nimport Testing\n\n@Test func starts() {\n    start()\n}\n", to: "Tests/LibTests/GizmoTests.swift", in: root)
            try TestSources.commitAll(in: root, message: "test target scan type fixture")
            try await TestSources.swiftBuildSuspending(packageAt: root)
        }
    }

    /// A type's `used by` tally states the scan's result where the scan found nothing, instead of advising a build, and the result is said once.
    @Test
    func aTypesTallyStatesTheScanResultInPlaceOfTheBuildAdvice() async throws {
        let output = try await Self.refs(of: "Gizmo", in: Self.typeFixture())

        #expect(output.contains("0 tests (the 1 Swift file in test targets does not write the name)"), "\(output)")
        #expect(!output.contains("build with"), "\(output)")
        #expect(!output.contains("tests not counted"), "\(output)")
        #expect(output.components(separatedBy: "does not write the name").count == 2, "\(output)")
    }
}
