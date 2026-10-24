//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Pins that a conformer row of a `where` answer, whichever mark it ends on, is read back to the file and line it names.
@Suite(.temporaryDirectories, .serialized)
struct ExactAnswerConformerRowTests {
    /// A built package with one protocol and two struct conformers.
    private static func fixture() async throws -> SharedBuiltFixture {
        try await SharedBuiltFixtures.process.fixture(for: Self.self, named: "conformer-row") { root in
            try TestSources.write(
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Lib",
                    targets: [.target(name: "Lib")]
                )
                """,
                to: "Package.swift",
                in: root
            )
            try TestSources.write("public protocol Greeter {}", to: "Sources/Lib/Greeter.swift", in: root)
            try TestSources.write("public struct Soldier: Greeter {}", to: "Sources/Lib/Soldier.swift", in: root)
            try TestSources.write("public struct Medic: Greeter {}", to: "Sources/Lib/Medic.swift", in: root)
            try TestSources.commitAll(in: root, message: "conformer row fixture")
            try await TestSources.swiftBuildSuspending(packageAt: root)
        }
    }

    /// The locations read from an answer of one row, in the order they sort.
    private static func located(_ row: String) -> [String] {
        ExactAnswer.locations(inWhereAnswer: row).map { "\($0.path):\($0.line)" }.sorted()
    }

    /// Each of the four marks leaves the row located where the unmarked row is.
    @Test
    func aMarkedRowIsLocatedLikeAnUnmarkedOne() {
        let bare = "  Lib.T1 — struct — Sources/Lib/T1.swift:1-2"
        for mark in [" — direct", " — indirect", " — direct; the index store does not have it", " — direct; the index store has it through another type"] {
            #expect(Self.located(bare + mark) == ["Sources/Lib/T1.swift:1"], "\(mark)")
            #expect(Self.located("  Lib.T1 — struct — Sources/Lib/T1.swift:1" + mark) == ["Sources/Lib/T1.swift:1"], "\(mark)")
        }
    }

    /// A staleness note after a mark changes nothing: the row is left out as it is without a mark.
    @Test
    func aStaleNoteAfterAMarkReadsAsItDidBefore() {
        for note in ["  (file deleted since last build)", "  (file changed since last build)"] {
            #expect(Self.located("  Lib.T1 — struct — Sources/Lib/T1.swift:1 — direct" + note) == Self.located("  Lib.T1 — struct — Sources/Lib/T1.swift:1" + note))
        }
    }

    /// The shapes recorded before conformer rows carried a mark are still read.
    @Test
    func theOldShapesAreStillRead() {
        #expect(Self.located("  Lib.T3 — struct — Sources/Lib/T3.swift:1-2") == ["Sources/Lib/T3.swift:1"])
        #expect(Self.located("  T3 — Sources/Lib/T3.swift:2") == ["Sources/Lib/T3.swift:2"])
    }

    /// A mark other than the three is not read as one.
    @Test
    func anotherMarkIsNotRead() {
        #expect(Self.located("  Lib.T1 — struct — Sources/Lib/T1.swift:1 — directly").isEmpty)
    }

    /// A plain `where` for a protocol yields every conformer's file.
    @Test
    func aProtocolAnswerLocatesEveryConformer() async throws {
        try await Self.fixture().withEngine { engine in
            let output = try await engine.lookup(symbol: "Greeter", freshness: engine.ensureFresh())
            let paths = Set(ExactAnswer.locations(inWhereAnswer: output).map(\.path))

            #expect(paths.isSuperset(of: ["Sources/Lib/Soldier.swift", "Sources/Lib/Medic.swift"]), "\(output)")
        }
    }

    /// An answer whose lines are located by number, with a block of rows under each `mention the name:` heading between them.
    private static var mentionAnswer: String {
        """
          Gizmo — struct — Sources/Lib/Gizmo.swift:1-9

          Sources/Lib/Use.swift (1): 4

        not in the build, mention the name:
          Tests/GizmoTests.swift (2):
            :34  | gizmo.record(…)
            :44  | …
          3 outside files not scanned

        new since last build, not in the store, mention the name:
          Sources/Lib/Fresh.swift (1):
            :7  | let a = Gizmo()

        uses: 1
          Sources/Lib/Later.swift (1): 12
        """
    }

    /// A site found by the name alone, in an unbuilt or a new file, is never located, under either heading, and the sections around the block still are.
    @Test
    func mentionRowsAreNeverLocated() {
        let located = ExactAnswer.locations(inWhereAnswer: Self.mentionAnswer)

        #expect(located == [
            ExactAnswer.Location(path: "Sources/Lib/Gizmo.swift", line: 1),
            ExactAnswer.Location(path: "Sources/Lib/Use.swift", line: 4),
            ExactAnswer.Location(path: "Sources/Lib/Later.swift", line: 12),
        ], "\(located)")
    }

    /// The lines an answer shows are the same set whether the mentions are rows or the compact line.
    @Test
    func shownLocationsAreTheSameForRowsAndTheCompactLine() {
        let rows = Self.mentionAnswer
        let compact = MentionRows.compacted(rows)

        #expect(compact != rows)
        #expect(ExactAnswer.shownLocations(inWhereAnswer: rows) == ExactAnswer.shownLocations(inWhereAnswer: compact), "\(compact)")
        #expect(ExactAnswer.locations(inWhereAnswer: rows) == ExactAnswer.locations(inWhereAnswer: compact), "\(compact)")
    }
}
