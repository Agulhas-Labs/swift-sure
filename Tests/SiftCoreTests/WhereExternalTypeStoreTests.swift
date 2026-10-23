//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `where Dep.member` with an index store, for a `Dep` a path dependency declares: with a fresh store the repository's uses of the member are the store's resolved references to the dependency's symbol, a same-named member of a repository type not among them; with a store the tree has moved past they are listed by written name under a stale header.
@Suite(.temporaryDirectories, .serialized)
struct WhereExternalTypeStoreTests {
    /// A built package depending on a path dependency's `Tally`, from a hidden directory the index never covers, whose `count` the package reads beside its own `Widget.count`.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "where-external-type") { root in
            try populate(root)
            try await TestSources.swiftBuildSuspending(packageAt: root)
        }
    }

    /// Writes and commits the package and its path dependency at `root`, unbuilt.
    private static func populate(_ root: URL) throws {
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Gizmo",
                dependencies: [.package(path: ".vendor/Dep")],
                targets: [.target(name: "GizmoCore", dependencies: [.product(name: "Dep", package: "Dep")])]
            )
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Dep",
                products: [.library(name: "Dep", targets: ["Dep"])],
                targets: [.target(name: "Dep")]
            )
            """,
            to: ".vendor/Dep/Package.swift",
            in: root
        )
        try TestSources.write(
            """
            public struct Tally {
                public init() {}

                public var count: Int {
                    2
                }
            }
            """,
            to: ".vendor/Dep/Sources/Dep/Tally.swift",
            in: root
        )
        try TestSources.write(total, to: "Sources/GizmoCore/Total.swift", in: root)
        try TestSources.commitAll(in: root, message: "external type fixture")
    }

    /// The package's file reading the dependency's `Tally.count` on line 10 beside its own `Widget.count`.
    private static let total = [
        "import Dep",
        "",
        "public struct Widget {",
        "    public var count: Int {",
        "        1",
        "    }",
        "}",
        "",
        "public func total(_ tally: Tally, _ widget: Widget) -> Int {",
        "    let first = tally.count",
        "    return first + widget.count",
        "}",
    ].joined(separator: "\n")

    /// The dependency's member is answered with its resolved references in the repository under a fresh header, neither the repository's same-named member nor the dependency's own source among them, and the same-named member listed as a declaration of its own.
    @Test
    func aDependencysMemberIsAnsweredWithItsResolvedReferences() async throws {
        try await Self.fixture().withEngine { engine in
            let output = try await engine.lookup(symbol: "Tally.count", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

            #expect(output.contains("semantic: fresh"), "\(output)")
            #expect(output.contains("Tally is declared outside this repository"), "\(output)")
            #expect(!output.contains("declared, but not under"), "\(output)")
            #expect(output.contains("other declarations of count in this repository (1):\n  GizmoCore.Widget.count — var — Sources/GizmoCore/Total.swift:4-6"), "\(output)")
            #expect(output.contains("references to Tally.count (1 in 1 file):"), "\(output)")
            #expect(output.contains(":10"), "\(output)")
            #expect(!output.contains(":11"), "\(output)")
            #expect(!output.contains("by written name"), "\(output)")
            #expect(!output.contains(".vendor"), "\(output)")
        }
    }

    /// A member the store records nowhere on the dependency's type is answered by written name, and the header says the store found no declaration for it rather than `fresh`.
    @Test
    func aMemberTheStoreRecordsNowhereIsUnresolved() async throws {
        try await Self.fixture().withEngine { engine in
            let output = try await engine.lookup(symbol: "Tally.size", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

            #expect(output.contains("semantic: fresh, 1 declaration not found in the store"), "\(output)")
            #expect(output.contains("Tally is declared outside this repository"), "\(output)")
            #expect(output.contains("no use spelled \"size\" anywhere in the working tree"), "\(output)")
        }
    }

    /// A file written since the build that writes the member makes the store stale for the answer, so the header says so and the uses are listed by written name, the edited file's new use among them.
    @Test
    func aStoreTheTreeMovedPastAnswersByWrittenNameUnderAStaleHeader() async throws {
        let root = try TestSources.makeTempRepo()
        try Self.populate(root)
        try await TestSources.swiftBuildSuspending(packageAt: root)
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        _ = try await engine.ensureFresh()
        try TestSources.write(Self.total + "\n\npublic func again(_ tally: Tally) -> Int {\n    tally.count\n}\n", to: "Sources/GizmoCore/Total.swift", in: root)

        let output = try await engine.lookup(symbol: "Tally.count", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

        #expect(output.contains("semantic: stale since last build ("), "\(output)")
        #expect(output.contains("Tally is declared outside this repository"), "\(output)")
        #expect(output.contains("\"count\" (3 uses by written name in 1 file; a same-named member of another type may be among them):"), "\(output)")
        #expect(output.contains(":15  in again(_:)"), "\(output)")
        #expect(!output.contains("references to Tally.count"), "\(output)")
    }
}
