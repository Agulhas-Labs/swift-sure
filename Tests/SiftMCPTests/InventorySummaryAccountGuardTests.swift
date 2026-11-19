//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The summary clause claims a lost pass line only where the summaries' count can be nothing else: a surplus ending, a repeated one or an already-spent summary each leave the test never reported.
@Suite(.temporaryDirectories)
struct InventorySummaryAccountGuardTests {
    private static func inventory(_ source: String, printing lines: [String]) async throws -> String {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: source)
        let (recorded, _) = try await RunInventoryNoteTests.run(in: repository, printing: lines, exiting: 0)
        return recorded.printed.split(separator: "\n").first { $0.hasPrefix("inventory:") }.map(String.init) ?? "\(recorded.printed)"
    }

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

    private static func swiftTesting(passed: [String], count: Int = 3) -> [String] {
        ["◇ Test run started."] + passed.map { "✔ Test \($0)() passed after 0.001 seconds." }
            + ["✔ Test run with \(count) tests in 1 suite passed after 0.900 seconds."]
    }

    @Test
    func anUnclaimedXCTestEndingLeavesTheTestNeverReportedWithoutTheClause() async throws {
        let lines = RunInventoryNoteTests.ended(["testOne", "testTwo", "testB"])
        let line = try await Self.inventory(RunInventoryNoteTests.threeMethodSource, printing: lines)

        #expect(line.contains("1 never reported: GizmoTests/PalletTests/testThree()"), "\(line)")
        #expect(!line.contains("summary counts"), "\(line)")
    }

    @Test
    func anUnclaimedSwiftTestingEndingLeavesTheTestNeverReportedWithoutTheClause() async throws {
        let lines = Self.swiftTesting(passed: ["anOrdinaryPass", "dimLampWorks", "shoutingWorks"])
        let line = try await Self.inventory(Self.swiftTestingSource, printing: lines)

        #expect(line.contains("1 never reported: GizmoTests/PalletTests/countIsOne()"), "\(line)")
        #expect(!line.contains("summary counts"), "\(line)")
    }

    @Test
    func aTestReportedTwiceLeavesTheTestNeverReportedWithoutTheClause() async throws {
        let lines = Self.swiftTesting(passed: ["anOrdinaryPass", "anOrdinaryPass", "dimLampWorks"])
        let line = try await Self.inventory(Self.swiftTestingSource, printing: lines)

        #expect(line.contains("never reported"), "\(line)")
        #expect(!line.contains("summary counts"), "\(line)")
    }

    @Test
    func severalUnreportedTestsSaySoInThePlural() async throws {
        let line = try await Self.inventory(Self.swiftTestingSource, printing: Self.swiftTesting(passed: ["anOrdinaryPass"]))

        #expect(line.contains("2 never reported: "), "\(line)")
        #expect(line.contains("summary counts all 3 run, none failing (pass lines were lost from the output; re-run to confirm)"), "\(line)")
    }

    @Test
    func aSkippedTestInAnXCTestSummaryIsNeverCalledPassed() async throws {
        let lines = Array(RunInventoryNoteTests.ended(["testOne", "testTwo"]).dropLast()) + ["Executed 3 tests, with 1 test skipped and 0 failures (0 unexpected) in 0.200 (0.204) seconds"]
        let line = try await Self.inventory(RunInventoryNoteTests.threeMethodSource, printing: lines)

        #expect(line.contains("XCTest's summary counts all 3 run, none failing (a pass line was lost"), "\(line)")
        #expect(!line.contains("passed ("), "\(line)")
    }

    @Test
    func bothFrameworksNameTheSummariesTogether() {
        let report = RunReport(
            errors: [], warnings: [], testFailures: [],
            summaryLines: [
                "✔ Test run with 2 tests in 1 suite passed after 0.900 seconds.",
                "Executed 1 test, with 0 failures (0 unexpected) in 0.200 (0.204) seconds",
            ],
            contract: .diagnostics, verdict: nil, tally: nil, totalLines: 0, testOutcomes: RunTestOutcomes()
        )

        #expect(report.summaryCount == RunSummaryCount(tests: 3, passed: true, framework: "Swift Testing's and XCTest's"))
    }

    @Test
    func resultLinesAlreadyCountedLostLeaveNoClauseOnTheNeverReportedOne() async throws {
        let lines = [
            "◇ Test run started.", "◇ Suite PalletTests started.",
            "◇ Test anOrdinaryPass() started.", "◇ Test countIsOne() started.",
            "✔ Test anOrdinaryPass() passed after 0.001 seconds.",
            "✔ Suite PalletTests passed after 0.002 seconds.",
            "✔ Test run with 3 tests in 1 suite passed after 0.002 seconds.",
        ]
        let line = try await Self.inventory(Self.swiftTestingSource, printing: lines)

        #expect(line.contains("1 never reported: GizmoTests/PalletTests/dimLampWorks() · 1 result line lost"), "\(line)")
        #expect(!line.contains("summary counts"), "\(line)")
    }
}
