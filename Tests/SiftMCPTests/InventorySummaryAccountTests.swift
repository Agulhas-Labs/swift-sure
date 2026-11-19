//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCore
import Testing

/// A pass line lost from a loaded run's output is told from a test that never ran by the frameworks' own summaries, and a spliced line is named on the clean line too.
@Suite(.temporaryDirectories)
struct InventorySummaryAccountTests {
    private static var swiftTestingSource: String {
        """
        import Testing

        struct PalletTests {
            @Test func anOrdinaryPass() {}
            @Test func countIsOne() {}
            @Test func dimLampWorks() {}
        }
        """
    }

    private static func inventory(_ source: String, printing lines: [String]) async throws -> String {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: source)
        let (recorded, _) = try await RunInventoryNoteTests.run(in: repository, printing: lines, exiting: 0)
        return recorded.printed.split(separator: "\n").first { $0.hasPrefix("inventory:") }.map(String.init) ?? "\(recorded.printed)"
    }

    private static let lostSwiftTestingLine = [
        "◇ Test run started.",
        "✔ Test anOrdinaryPass() passed after 0.010 seconds.",
        "✔ Test dimLampWorks() passed after 0.001 seconds.",
        "✔ Test run with 3 tests in 1 suite passed after 0.900 seconds.",
    ]

    @Test
    func aSwiftTestingSummaryCoveringTheUnreportedTestSaysAPassLineWasLost() async throws {
        let line = try await Self.inventory(Self.swiftTestingSource, printing: Self.lostSwiftTestingLine)

        #expect(line.contains("1 never reported: GizmoTests/PalletTests/countIsOne(); Swift Testing's summary counts all 3 run, none failing (a pass line was lost from the output; re-run to confirm)"), "\(line)")
    }

    @Test
    func anXCTestSummaryCoveringTheUnreportedTestSaysAPassLineWasLost() async throws {
        let lines = RunInventoryNoteTests.ended(["testOne", "testTwo"]).dropLast() + ["Executed 3 tests, with 0 failures (0 unexpected) in 0.200 (0.204) seconds"]
        let line = try await Self.inventory(RunInventoryNoteTests.threeMethodSource, printing: Array(lines))

        #expect(line.contains("1 never reported: GizmoTests/PalletTests/testThree(); XCTest's summary counts all 3 run, none failing (a pass line was lost from the output; re-run to confirm)"), "\(line)")
    }

    @Test
    func aSummaryThatDoesNotCoverTheUnreportedTestLeavesTheWordingAlone() async throws {
        let lines = Array(Self.lostSwiftTestingLine.dropLast()) + ["✔ Test run with 2 tests in 1 suite passed after 0.900 seconds."]
        let line = try await Self.inventory(Self.swiftTestingSource, printing: lines)

        #expect(line.contains("1 never reported: GizmoTests/PalletTests/countIsOne()"), "\(line)")
        #expect(!line.contains("summary counts"), "\(line)")
    }

    @Test
    func aGarbledLineIsNamedOnTheCleanLineToo() async throws {
        let lines = [
            "◇ Test run started.",
            "✔ Test anOrdinaryPass() passed after 0.010 seconds.",
            "✔ Test anOrdinaryPass(ne() passed after 0.851 seconds.",
            "✔ Test countIsOne() passed after 0.010 seconds.",
            "✔ Test dimLampWorks() passed after 0.001 seconds.",
            "✔ Test run with 3 tests in 1 suite passed after 0.900 seconds.",
        ]
        let line = try await Self.inventory(Self.swiftTestingSource, printing: lines)

        #expect(line.hasPrefix("inventory: 3 declared, 3 reported (1 report line garbled (output lines spliced?): anOrdinaryPass(ne()"), "\(line)")
    }
}
