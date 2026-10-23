//
// Copyright © Agulhas Labs
//

import Foundation

/// The clauses a totals line carries for a run whose test bundle `xcodebuild` restarted, so the restarted pass's summary never stands for the run.
struct RunRestartedTotals {
    /// Says the bundle restarted and names the test running at each restart: `bundle restarted during A.one, then B.two`.
    ///
    /// A restart that left no test open is named by no test, and where none of several did the clause counts them.
    static func note(_ restarts: [RunRestart]) -> String {
        let named = restarts.map { $0.open.isEmpty ? "no test" : $0.open.joined(separator: ", ") }
        guard restarts.contains(where: { !$0.open.isEmpty }) else {
            return restarts.count == 1 ? "bundle restarted" : "bundle restarted \(restarts.count) times"
        }
        return "bundle restarted during \(named.joined(separator: ", then "))"
    }

    /// The count clauses of a restarted run, XCTest's then Swift Testing's.
    ///
    /// A framework's count is split into the pass after the restart and the pass before it only where that framework had a test open, or had reported one, before a marker; otherwise the plain clause stands, since a restart in the other framework's tests says nothing of this one.
    static func counts(
        report: RunReport,
        swiftTesting: [String],
        xctest: [String],
        plain: (xctest: String?, swiftTesting: String?),
        swiftTestingSkipNote: String,
        xctestSkipNote: String
    ) -> [String] {
        let xctestClause = splitsXCTest(report.restarts)
            ? RunRestartedXCTest.counts(report: report, lines: xctest, skipNote: xctestSkipNote)
            : plain.xctest
        let swiftTestingClause = splitsSwiftTesting(report.restarts)
            ? swiftTestingCounts(report: report, lines: swiftTesting, skipNote: swiftTestingSkipNote)
            : plain.swiftTesting
        return [xctestClause, swiftTestingClause].compactMap(\.self)
    }

    /// The passes of one framework, the last first: `after` is the text counting the pass after the last restart and `before` the number that reported in each earlier pass.
    static func passes(after: String, before: [Int]) -> [String] {
        guard before.count > 1 else {
            return ["\(after) after the restart", "\(before.first ?? 0) before it"]
        }
        var passes = ["\(after) after the last restart", "\(before[0]) before the first restart"]
        for index in 1 ..< before.count {
            passes.append("\(before[index]) between restart \(index) and \(index + 1)")
        }
        return passes
    }

    /// Swift Testing's counts for the pass after the last restart and for each pass before it, each under its own name, or `nil` where the log shows no Swift Testing test.
    ///
    /// `skipNote` is the skipped clause the plain counts carry, which a restart does not change the meaning of.
    static func swiftTestingCounts(report: RunReport, lines: [String], skipNote: String) -> String? {
        let restarts = report.restarts
        guard let last = restarts.last, !lines.isEmpty || !report.testOutcomes.swiftTestingNames.isEmpty else {
            return nil
        }
        let tallies = lines.dropFirst(last.summariesBefore).map { RunTestTally.parse(String(RunOutputFilter.undecorated($0))) }
        let after: String
        if !tallies.isEmpty, tallies.allSatisfy({ $0 != nil }) {
            let readable = tallies.compactMap(\.self)
            after = "\(count(readable.reduce(0) { $0 + $1.tests }, "test")) in \(count(readable.reduce(0) { $0 + $1.suites }, "suite"))"
        } else {
            let afterReported = RunRestartReader.reported(in: report.testOutcomes) - restarts.reduce(0) { $0 + $1.reported }
            after = count(afterReported, "test")
        }
        let failures = lines.compactMap { RunTestTally.parse(String(RunOutputFilter.undecorated($0)))?.failures }.reduce(0, +)
        let passes = passes(after: after, before: restarts.map(\.reported))
        return "Swift Testing \(passes.joined(separator: ", "))\(failingSwiftTesting(report: report, issues: failures))\(skipNote)"
    }

    /// Whether the restarts leave a Swift Testing count to split: a Swift Testing test was open or had reported before a marker.
    static func splitsSwiftTesting(_ restarts: [RunRestart]) -> Bool {
        restarts.contains { $0.reported > 0 || $0.swiftTestingOpen }
    }

    /// Whether the restarts leave an XCTest count to split: an XCTest test was open or had reported before a marker.
    static func splitsXCTest(_ restarts: [RunRestart]) -> Bool {
        restarts.contains { $0.xctestReported > 0 || $0.xctestOpen }
    }

    /// The failing clause of a restarted run, counted from the per-test endings, since the pass that died printed no summary to count its failures from.
    private static func failingSwiftTesting(report: RunReport, issues: Int) -> String {
        let outcomes = report.testOutcomes
        let failed = outcomes.swiftTestingNames.filter { outcomes.lastEndings[$0] == .failed }
        guard !failed.isEmpty else {
            return RunFailingTests.swiftTesting(issues: issues, outcomes: outcomes)
        }
        let perTest = failed.compactMap { outcomes.failureIssues[$0] }
        let recorded = perTest.count == failed.count ? perTest.reduce(0, +) : failed.count
        return RunFailingTests.clause(failing: failed.count, recorded: max(issues, recorded), unit: "issue")
    }

    /// `summaries` less the Swift Testing sentences that read `passed`, where the run restarted and did not pass.
    ///
    /// The restarted pass's own `passed` sentence is a statement about a few tests over a run that failed, and quoting it beside `** TEST FAILED **` reads as the run's verdict.
    static func withholdingPasses(_ summaries: [String], report: RunReport, exitCode: Int32) -> [String] {
        guard !report.restarts.isEmpty, exitCode != 0 || report.verdict?.state != .succeeded else {
            return summaries
        }
        return summaries.filter { line in
            let undecorated = RunOutputFilter.undecorated(line)
            return !(undecorated.hasPrefix("Test run with ") && undecorated.contains(" passed after "))
        }
    }

    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
