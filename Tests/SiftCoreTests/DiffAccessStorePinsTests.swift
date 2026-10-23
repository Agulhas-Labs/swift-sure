//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with a fresh index store: a witness the store resolves is never listed, the uses of a compiled declaration are the store's, and a file in a target the last build did not compile falls back to name matching and says so.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessStorePinsTests {
    /// A built package whose last commit adds a type conforming to a protocol of its own, used from another module of the package, and a function in a target the build left out.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-store") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),
                        .target(name: "GizmoTools", dependencies: ["GizmoKit"]),
                        .target(name: "GizmoExtras"),
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("public protocol Stocking {\n    func restock()\n}\n", to: "Sources/GizmoKit/Stocking.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.write("func spare() {}\n", to: "Sources/GizmoExtras/Extra.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write(
                """
                public struct Shelf: Stocking {
                    public init() {}

                    public func restock() {}

                    public func count() -> Int {
                        0
                    }
                }
                """,
                to: "Sources/GizmoKit/Shelf.swift",
                in: root
            )
            try TestSources.write("import GizmoKit\n\nfunc run() -> Int {\n    Shelf().count()\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.write("func spare() {}\n\npublic func polish() {}\n", to: "Sources/GizmoExtras/Extra.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root, arguments: ["--target", "GizmoTools"])
        }
    }

    /// The last commit's diff, read by the fixture's engine.
    private static func diffOfTheLastCommit() async throws -> String {
        let fixture = try await fixture()
        return try await fixture.withEngine { engine in
            let range = try DiffRange.resolve("HEAD", git: GitContext(repoRoot: fixture.root))
            return try await engine.diff(options: DiffOptions(range: range), freshness: engine.ensureFresh())
        }
    }

    /// `restock()` satisfies `Stocking.restock()` by the store's requirement relation: it is counted as not judged and never listed, while its type's compiled members are judged by the store's uses.
    @Test func aWitnessTheStoreResolvesIsNeverListed() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("semantic: fresh"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.Shelf.count()  Sources/GizmoKit/Shelf.swift:6  public → package: used only from GizmoTools, in this package"), "\(answer)")
        #expect(answer.contains("  not judged: 1 protocol witness"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Shelf.restock()"), "\(answer)")
    }

    /// `GizmoExtras` was not compiled by the last build, so its declaration's uses are name-matched, and the heading names it as the one name-matched declaration.
    @Test func aFileInAnUncompiledTargetFallsBackToNameMatching() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("access: this range put 4 declarations at public, 1 with no use outside their module, 3 used only inside its package"), "\(answer)")
        #expect(answer.contains("  uses resolved by the index store, except name-matched over the working tree for: GizmoExtras.polish()"), "\(answer)")
        #expect(answer.contains("  + GizmoExtras.polish()  Sources/GizmoExtras/Extra.swift:3  public → internal: no use by that name outside module GizmoExtras"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.Shelf  Sources/GizmoKit/Shelf.swift:1  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }
}
