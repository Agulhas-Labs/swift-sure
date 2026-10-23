//
// Copyright © Agulhas Labs
//

import Foundation

/// XCTest's count clause for a run whose test bundle `xcodebuild` restarted, so the relaunched pass's counter never stands for the run.
struct RunRestartedXCTest {
    /// XCTest's counts for the pass after the last restart and for each pass before it, each under its own name.
    ///
    /// The relaunched process prints a counter of its own pass alone, so the passes before it are counted from the per-test endings the log shows, and the failing tests the same way, since the pass that died printed no counter. `skipNote` is the skipped clause the plain counts carry.
    static func counts(report: RunReport, lines: [String], skipNote: String) -> String {
        let outcomes = report.testOutcomes
        let before = report.restarts.map(\.xctestReported)
        let counters = lines.compactMap { RunOutputFilter.ExecutedCounts(line: $0) }
        let after = !lines.isEmpty && counters.count == lines.count
            ? counters.reduce(0) { $0 + $1.tests }
            : max(0, RunRestartReader.xctestReported(in: outcomes) - before.reduce(0, +))
        let failed = outcomes.lastEndings.filter { $0.value == .failed && !outcomes.swiftTestingNames.contains($0.key) }.count
        let recorded = max(counters.reduce(0) { $0 + $1.failures }, failed)
        let failing = RunFailingTests.clause(failing: failed > 0 ? failed : nil, recorded: recorded, unit: "recorded failure")
        let passes = RunRestartedTotals.passes(after: RunRestartedTotals.count(after, "test"), before: before)
        return "XCTest \(passes.joined(separator: ", "))\(failing)\(skipNote)"
    }

    /// How many XCTest tests the run skipped, counted from the per-test endings as well as the counters, since the pass that died printed no counter.
    static func skipped(report: RunReport, lines: [String]) -> Int {
        let outcomes = report.testOutcomes
        let counted = lines.compactMap { RunOutputFilter.ExecutedCounts(line: $0)?.skipped }.reduce(0, +)
        let ended = outcomes.lastEndings.filter { $0.value == .skipped && !outcomes.swiftTestingNames.contains($0.key) }.count
        return max(counted, ended)
    }
}
