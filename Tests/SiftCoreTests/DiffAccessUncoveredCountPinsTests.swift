//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with an index store: the line saying how the uses were found admits the files it name-matched, also where none of them held a match.
@Suite(.temporaryDirectories, .serialized)
struct DiffAccessUncoveredCountPinsTests {
    /// A package whose last commit adds an unused public function to a compiled module, built with or without a test target the build leaves out.
    private static func fixture(withTests: Bool) async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: withTests ? "diff-access-count-tests" : "diff-access-count-none") { root in
            let testsEntry = withTests ? "\n        .testTarget(name: \"GizmoTests\", dependencies: [\"GizmoKit\"])," : ""
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Depot",
                    targets: [
                        .target(name: "GizmoKit"),\(testsEntry)
                    ]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            if withTests {
                try TestSources.write("import Testing\n\n@Test func nothing() {}\n", to: "Tests/GizmoTests/GizmoTests.swift", in: root)
            }
            try TestSources.commitAll(in: root, message: "base")
            try TestSources.write("struct Gizmo {}\n\npublic func idle() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
            try TestSources.commitAll(in: root, message: "range")
            try await TestSources.swiftBuildSuspending(packageAt: root)
        }
    }

    private static func diffOfTheLastCommit(withTests: Bool) async throws -> String {
        let fixture = try await fixture(withTests: withTests)
        return try await fixture.withEngine { engine in
            let range = try DiffRange.resolve("HEAD", git: GitContext(repoRoot: fixture.root))
            return try await engine.diff(options: DiffOptions(range: range), freshness: engine.ensureFresh())
        }
    }

    /// The test target was not built and nothing in it uses `idle()`: the "no use" rests partly on name matching its file, and the line says one file was name-matched.
    @Test func aCountNamesTheUncoveredFilesNoneOfWhichHeldAMatch() async throws {
        let answer = try await Self.diffOfTheLastCommit(withTests: true)

        #expect(answer.contains("GizmoKit.idle()  Sources/GizmoKit/Gizmo.swift:3  public → internal: no use outside module GizmoKit"), "\(answer)")
        #expect(answer.contains("  uses resolved by the index store, in the targets the last build compiled; name-matched in 1 file the last build left out or that changed since\n"), "\(answer)")
    }

    /// Every file is one the build compiled: nothing was name-matched, and the line carries no clause.
    @Test func noClauseWhereTheStoreCoversEveryFile() async throws {
        let answer = try await Self.diffOfTheLastCommit(withTests: false)

        #expect(answer.contains("  uses resolved by the index store, in the targets the last build compiled\n"), "\(answer)")
        #expect(!answer.contains("name-matched in"), "\(answer)")
    }
}
