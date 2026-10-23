//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A test bundle `xcodebuild` restarted is never reported by its restarted pass alone.
struct RunRestartedBundleTotalsTests {
    private static var marker: String {
        "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
    }

    private static func passed(_ name: String) -> [String] {
        ["◇ Test \(name) started.", "✔ Test \(name) passed after 0.001 seconds."]
    }

    private static func answer(_ lines: [String], exitCode: Int32) -> String {
        var filter = RunOutputFilter(invokedAs: ["xcodebuild", "test"])
        for line in lines {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: exitCode)
        return RunReportRenderer(kind: .xcodebuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Depot"))
            .render(report, exitCode: exitCode, logURL: nil)
    }

    private static func totals(_ answer: String) -> String {
        answer.split(separator: "\n").first { $0.hasPrefix("totals:") }.map(String.init) ?? ""
    }

    private static let oneRestart: [String] = ["◇ Test run started."] + passed("adds()") + passed("subtracts()") + [
        "◇ Test multiplies() started.", "", marker, "",
        "◇ Test run started.",
    ] + passed("divides()") + [
        "✔ Test run with 20 tests in 28 suites passed after 2.016 seconds.",
        "** TEST FAILED **",
    ]

    @Test
    func theTotalsLineNamesTheRestartTheTestRunningAndBothPasses() {
        let answer = Self.answer(Self.oneRestart, exitCode: 65)

        #expect(Self.totals(answer) == "totals: ✘ failed · bundle restarted during multiplies() · Swift Testing 20 tests in 28 suites after the restart, 2 before it, 0 skipped")
    }

    @Test
    func theRestartedPassesPassedSentenceIsNotQuotedUnderAFailedRun() {
        let answer = Self.answer(Self.oneRestart, exitCode: 65)

        #expect(!answer.contains("Test run with 20 tests"))
        #expect(!Self.totals(answer).contains("passed"))
    }

    @Test
    func aRestartWithNoTestOpenNamesNone() {
        let log = ["◇ Test run started."] + Self.passed("adds()") + ["", Self.marker, ""] + Self.passed("divides()")
            + ["✔ Test run with 3 tests in 1 suite passed after 2.016 seconds.", "** TEST FAILED **"]

        #expect(Self.totals(Self.answer(log, exitCode: 65)).contains("· bundle restarted · Swift Testing 3 tests in 1 suite after the restart, 1 before it"))
    }

    @Test
    func severalRestartsAreNamedInOrderWithEachPassCounted() {
        let log = ["◇ Test run started."] + Self.passed("a()") + Self.passed("b()") + ["◇ Test one() started.", "◇ Test two() started.", Self.marker]
            + Self.passed("c()") + ["◇ Test three() started.", Self.marker] + Self.passed("d()")
            + ["✔ Test run with 4 tests in 2 suites passed after 1.000 seconds.", "** TEST FAILED **"]

        #expect(Self.totals(Self.answer(log, exitCode: 65)) == "totals: ✘ failed · bundle restarted during one(), two(), then three() · Swift Testing 4 tests in 2 suites after the last restart, 2 before the first restart, 1 between restart 1 and 2, 0 skipped")
    }

    @Test
    func aRestartedRunThatExitedNonZeroNeverReadsAsPassed() {
        let log = ["◇ Test run started.", "◇ Test x() started.", Self.marker] + Self.passed("y()")
            + ["✔ Test run with 1 test in 1 suite passed after 1.000 seconds."]
        let answer = Self.answer(log, exitCode: 65)

        #expect(Self.totals(answer).contains("bundle restarted during x()"))
        #expect(!answer.contains("passed after"))
    }

    @Test
    func theInventoryOfARestartedRunNeverTakesItsCleanForm() {
        let reconciliation = RunReconciliation(
            counts: ReconciliationCounts(expected: 3, ran: 3, passed: 3, failed: 0, skipped: 0, missing: 0, duplicated: 0),
            scope: RunReconciliation.Scope(manifest: "Package.swift", targets: ["GizmoTests"], conditionalTargets: false, logPath: "run.log"),
            iterations: 1,
            missing: [],
            shortfalls: [],
            duplicated: [],
            failed: [],
            excluded: [],
            undecided: [],
            unclaimed: [],
            outsideScope: [],
            notes: []
        )
        let check = RunInventoryCheck.reconciled(reconciliation)
        let restart = RunRestart(open: ["x()"], reported: 3, summariesBefore: 0)

        #expect(check.lines(after: nil).first?.contains("bundle restarted") == false)
        #expect(check.lines(after: nil, restarts: [restart]).first?.contains("bundle restarted") == true)
    }
}
