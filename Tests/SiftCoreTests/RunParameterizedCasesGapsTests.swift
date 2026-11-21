//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The parameterized-case count reaches the two totals shapes that once printed none: several Swift Testing tallies that are not summed, and a restarted bundle's passes.
struct RunParameterizedCasesGapsTests {
    private static var marker: String {
        "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
    }

    private static func totals(of lines: [String], invokedAs arguments: [String], kind: RunCommandKind, exitCode: Int32) -> String {
        var filter = RunOutputFilter(invokedAs: arguments)
        for line in lines {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: exitCode)
        let answer = RunReportRenderer(kind: kind, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"), selector: RunTestSelector.named(in: arguments))
            .render(report, exitCode: exitCode, logURL: nil)
        return answer.split(separator: "\n").map(String.init).first { $0.hasPrefix("totals:") } ?? "no totals line in \(answer)"
    }

    /// Two parameterized tests (4 and 3 cases) among three plain ones, and a second tally that cannot be read: the tallies are not summed, and the cases beyond the tests are said once for them.
    @Test
    func unsummedTalliesSayHowManyMoreCasesThanTestsRan() {
        var lines = ["◇ Test run started.", "◇ Suite OrchardTests started."]
        lines.append("✔ Test pickedRows(count:) with 4 test cases passed after 0.001 seconds.")
        lines.append("✔ Test bushels(size:) with 3 test cases passed after 0.001 seconds.")
        for index in 1 ... 3 {
            lines.append("✔ Test plain\(index)() passed after 0.001 seconds.")
        }
        lines.append("✔ Suite OrchardTests passed after 0.010 seconds.")
        lines.append("✔ Test run with 5 tests in 1 suite passed after 0.010 seconds.")
        lines.append("✔ Test run with several tests in 2 suites passed after 0.010 seconds.")
        let line = Self.totals(of: lines, invokedAs: ["swift", "test"], kind: .swiftTest, exitCode: 0)

        #expect(line.contains("Swift Testing 2 tallies, not summed — 5 tests in 1 suite; tally 2 unreadable; 5 more cases than tests across them"), "\(line)")
    }

    /// Unsummed tallies of tests that were each one case print what they always printed.
    @Test
    func unsummedTalliesOfPlainTestsSayNothingOfCases() {
        let lines = ["◇ Test run started.", "✔ Test plain1() passed after 0.001 seconds.", "✔ Test run with 1 test in 1 suite passed after 0.010 seconds.", "✔ Test run with several tests in 2 suites passed after 0.010 seconds."]
        let line = Self.totals(of: lines, invokedAs: ["swift", "test"], kind: .swiftTest, exitCode: 0)

        #expect(line.contains("tally 2 unreadable"), "\(line)")
        #expect(!line.contains("cases"), "\(line)")
    }

    /// A parameterized test that reported before the restart still counts, so the restarted run's totals carry the cases of the whole run beside the tests of every pass.
    @Test
    func aRestartedRunsTotalsCarryTheCaseCount() {
        let lines = [
            "◇ Test run started.",
            "✔ Test pickedRows(count:) with 4 test cases passed after 0.001 seconds.",
            "✔ Test plain1() passed after 0.001 seconds.",
            "◇ Test plain2() started.", "", Self.marker, "",
            "◇ Test run started.",
            "✔ Test plain3() passed after 0.001 seconds.",
            "✔ Test run with 1 test in 1 suite passed after 0.010 seconds.",
            "** TEST FAILED **",
        ]
        let line = Self.totals(of: lines, invokedAs: ["xcodebuild", "test"], kind: .xcodebuild, exitCode: 65)

        #expect(line.contains("Swift Testing 1 test in 1 suite after the restart, 2 before it (6 cases), 0 skipped"), "\(line)")
    }

    /// A restarted run with no parameterized test keeps the clause it had.
    @Test
    func aRestartedRunWithoutExtraCasesPrintsNoCaseCount() {
        let lines = [
            "◇ Test run started.",
            "✔ Test plain1() passed after 0.001 seconds.",
            "◇ Test plain2() started.", "", Self.marker, "",
            "◇ Test run started.",
            "✔ Test plain3() passed after 0.001 seconds.",
            "✔ Test run with 1 test in 1 suite passed after 0.010 seconds.",
            "** TEST FAILED **",
        ]
        let line = Self.totals(of: lines, invokedAs: ["xcodebuild", "test"], kind: .xcodebuild, exitCode: 65)

        #expect(line.contains("Swift Testing 1 test in 1 suite after the restart, 1 before it, 0 skipped"), "\(line)")
        #expect(!line.contains("cases"), "\(line)")
    }
}
