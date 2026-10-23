//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the count line of an `affected` answer taken while the index store is still warming.
@Suite(.temporaryDirectories, .serialized)
struct AffectedWarmingCountLineTests {
    private static func answer(warming: Bool) async throws -> String {
        let root = try TestSources.makeTempRepo()
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
        try TestSources.write("public struct Widget {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.write("import XCTest\n@testable import Lib\n\nfinal class LampTests: XCTestCase {\n    let widget = Widget()\n    func testOne() {}\n}\n", to: "Tests/LibTests/LampTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try await TestSources.swiftBuild(packageAt: root)
        try TestSources.write("public struct Widget {\n    public init() {}\n    public func shine() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        let engine = try SiftEngine(directory: root)
        if warming {
            engine.openBudget = 0
        } else {
            try await engine.awaitSemanticStore()
        }
        return try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())
    }

    /// A warming answer's count line names its source, and the caveats it makes redundant are not printed again.
    @Test
    func aWarmingCountLineSaysItIsSyntacticAndTheRepeatedCaveatsCollapse() async throws {
        let output = try await Self.answer(warming: true)

        #expect(output.contains("affected tests (1 in 1 target, syntactic: the index store is still warming; re-run for the resolved count):"), "\(output)")
        #expect(!output.contains("resolved references: UNAVAILABLE"), "\(output)")
        #expect(output.contains("LibTests.LampTests — 1 hop — Tests/LibTests/LampTests.swift"), "\(output)")
        #expect(!output.contains("1 hop, name match"), "\(output)")
    }

    /// The resolved line is unchanged.
    @Test
    func aResolvedCountLineCarriesNoSourceClause() async throws {
        let output = try await Self.answer(warming: false)

        #expect(output.contains("affected tests (1 in 1 target"), "\(output)")
        #expect(!output.contains("index store is still warming"), "\(output)")
    }
}
