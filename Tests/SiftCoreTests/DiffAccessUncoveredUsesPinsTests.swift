//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with an index store that does not cover every use: a use in a target the last build left out, or in a file changed since it, is matched by name and counted beside the store's, and the line saying how the uses were found names those files.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessUncoveredUsesPinsTests {
    /// A package built without its tests, whose last commit adds two public functions to a compiled module: one used only from the test target, which imports the module plainly, and one whose call in another module was written after the build.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "diff-access-uncovered") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),
                        .target(name: "GizmoTools", dependencies: ["GizmoKit"]),
                        .testTarget(name: "GizmoTests", dependencies: ["GizmoKit"]),
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("import GizmoKit\n\nfunc run() {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
            try TestSources.write("import Testing\n\n@Test func nothing() {}\n", to: "Tests/GizmoTests/GizmoTests.swift", in: root)
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write("struct Gizmo {}\n\npublic func restock() {}\n\npublic func shelve() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.write("import GizmoKit\nimport Testing\n\n@Test func stock() {\n    restock()\n}\n", to: "Tests/GizmoTests/GizmoTests.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root)
            try TestSources.write("import GizmoKit\n\nfunc run() {\n    shelve()\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
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

    /// `restock()` is used only from the uncompiled test target and `shelve()` only from a file written after the build: the store holds neither use, so both are name-matched there, and each allows `package`, never `internal`.
    @Test func aUseTheStoreDoesNotCoverIsNameMatchedAndCounted() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains("access: this range put 2 declarations at public, 2 used only inside its package"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:3  public → package: used only from GizmoTests, in this package"), "\(answer)")
        #expect(answer.contains("  + GizmoKit.shelve()  Sources/GizmoKit/Gizmo.swift:5  public → package: used only from GizmoTools, in this package"), "\(answer)")
        #expect(!answer.contains("public → internal"), "\(answer)")
    }

    /// The line saying how the uses were found says which were name-matched: those in the files the store does not cover.
    @Test func theResolutionLineNamesTheFilesMatchedByName() async throws {
        let answer = try await Self.diffOfTheLastCommit()

        #expect(answer.contains(
            "  uses resolved by the index store, in the targets the last build compiled; name-matched in the files the last build left out or that changed since: Sources/GizmoTools/Tool.swift, Tests/GizmoTests/GizmoTests.swift"
        ), "\(answer)")
    }
}
