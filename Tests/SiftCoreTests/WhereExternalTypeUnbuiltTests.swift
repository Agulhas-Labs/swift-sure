//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `where Dep.member` with an index store that holds no unit for the file using the member: a path dependency's `Tally.count`, used only in a test target the build never compiled, is listed by written name and the header says `partial`, never `fresh`.
@Suite(.temporaryDirectories, .serialized)
struct WhereExternalTypeUnbuiltTests {
    /// The only use of the dependency's member is in an unbuilt test file, which the answer lists by written name in place of an absence, under a header that is not `fresh`.
    @Test
    func aUseInAnUnbuiltTestTargetIsListedAndTheHeaderIsNotFresh() async throws {
        let root = try TestSources.makeTempRepo()
        try Self.populate(root)
        try await TestSources.swiftBuildSuspending(packageAt: root)
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()

        let output = try await engine.lookup(symbol: "Tally.count", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

        #expect(output.contains("Tally is declared outside this repository"), "\(output)")
        #expect(output.contains("Tests/GizmoTests/CountTests.swift"), "\(output)")
        #expect(!output.contains("semantic: fresh"), "\(output)")
        #expect(output.contains("semantic: partial"), "\(output)")
        #expect(output.contains("not in the build, mention the name: Tests/GizmoTests/CountTests.swift:7"), "\(output)")
        #expect(!output.contains("no reference to Tally.count in this repository"), "\(output)")
    }

    /// Writes and commits a package whose library returns a path dependency's `Tally` and whose test target, never built, reads its `count`.
    private static func populate(_ root: URL) throws {
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Gizmo",
                dependencies: [.package(path: ".vendor/Dep")],
                targets: [
                    .target(name: "GizmoCore", dependencies: [.product(name: "Dep", package: "Dep")]),
                    .testTarget(name: "GizmoTests", dependencies: ["GizmoCore", .product(name: "Dep", package: "Dep")]),
                ]
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
        try TestSources.write(
            """
            import Dep

            public func make() -> Tally {
                Tally()
            }
            """,
            to: "Sources/GizmoCore/Make.swift",
            in: root
        )
        try TestSources.write(
            """
            import Dep
            import GizmoCore
            import Testing

            @Test
            func counts() {
                #expect(make().count == 2)
            }
            """,
            to: "Tests/GizmoTests/CountTests.swift",
            in: root
        )
        try TestSources.commitAll(in: root, message: "external type in an unbuilt test target")
    }
}
