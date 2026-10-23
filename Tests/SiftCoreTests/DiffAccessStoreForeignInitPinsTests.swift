//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with a fresh index store counts an implicit-member `init(` call in a file of another module the store does not cover as a use of every initializer of each module that file imports.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessStoreForeignInitPinsTests {
    /// A built package whose last commit adds initializers to `GizmoKit` and `SproutKit`, with a file added to `GizmoTools` after the build.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-store-cross-module-implicit-init") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),
                        .target(name: "SproutKit"),
                        .target(name: "GizmoTools", dependencies: ["GizmoKit"]),
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("struct Bud {}\n", to: "Sources/SproutKit/Bud.swift", in: root)
            try TestSources.write("func run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write(DiffAccessForeignInitPinsTests.crate + "\n\npublic func make() -> Holder {\n    Holder(crate: Crate())\n}\n", to: "Sources/GizmoKit/Crate.swift", in: root)
            try TestSources.write("public struct Pail {\n    public init() {}\n}\n", to: "Sources/SproutKit/Pail.swift", in: root)
            try TestSources.write("import GizmoKit\n\nfunc run() {\n    _ = make()\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root)
            try TestSources.write(DiffAccessForeignInitPinsTests.refill, to: "Sources/GizmoTools/Later.swift", in: root)
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

    /// Narrowing `Crate.init()` to `internal` fails with "'Crate' initializer is inaccessible due to 'internal' protection level": the implicit-member call sits in a file written after the build, which the store has no reference from.
    @Test func anImplicitInitializerInAnotherModulesUncoveredFileAllowsPackage() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("  + GizmoKit.Crate.init()  Sources/GizmoKit/Crate.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
        #expect(answer.contains("Sources/GizmoTools/Later.swift"), "\(answer)")
    }

    /// An initializer of a module the uncovered file does not import keeps its suggestion.
    @Test func anInitializerOfAModuleNotImportedThereLeavesInternal() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("  + SproutKit.Pail.init()  Sources/SproutKit/Pail.swift:2  public → internal: no use outside module SproutKit"), "\(answer)")
    }
}
