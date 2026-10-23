//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the failure clause of the `totals:` line: it counts the tests that failed, and names the framework's own count by its unit, so two tests that each failed twice are not read as four failed tests.
struct RunFailingCountWordingTests {
    private static func totals(_ lines: [String], contract: RunVerdict.Contract = .runTally, exitCode: Int32 = 1) -> String {
        var filter = RunOutputFilter(expecting: contract)
        for line in lines {
            filter.consume(line: line)
        }
        let answer = RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Depot"))
            .render(filter.finish(exitCode: exitCode), exitCode: exitCode, logURL: nil)
        let anchored = answer.split(separator: "\n").filter { $0.hasPrefix("totals:") }
        return String(anchored.first ?? "")
    }

    private static let twoOfFour = [
        "✘ Test boils() failed after 0.001 seconds with 2 issues.",
        "✘ Test steeps() failed after 0.001 seconds with 2 issues.",
        "✔ Test countIsOne() passed after 0.001 seconds.",
        "✔ Test aFailingTest() passed after 0.001 seconds.",
    ]

    /// The defect: `4 tests, 4 failures` over two failed tests read as every test failed.
    @Test
    func twoFailedTestsOfFourWithFourIssuesAreCountedAsTwoFailing() {
        let line = Self.totals(Self.twoOfFour + ["✘ Test run with 4 tests in 1 suite failed after 0.020 seconds with 4 issues."])

        #expect(line == "totals: ✘ failed · Swift Testing 4 tests in 1 suite, 2 failing (4 issues), 0 skipped")
        #expect(!line.contains("failures"))
    }

    /// The parenthesis is the tool's own count and appears only where it differs from the failing-test count.
    @Test
    func theIssueCountIsLeftOutWhereItEqualsTheFailingTestCount() {
        let lines = [
            "✘ Test boils() failed after 0.001 seconds with 1 issue.",
            "✔ Test countIsOne() passed after 0.001 seconds.",
            "✘ Test run with 2 tests in 1 suite failed after 0.020 seconds with 1 issue.",
        ]

        #expect(Self.totals(lines) == "totals: ✘ failed · Swift Testing 2 tests in 1 suite, 1 failing, 0 skipped")
    }

    /// Per-test issue counts that do not add up to the summary's leave the issues alone, under their unit.
    @Test
    func perTestCountsThatDoNotAddUpLeaveTheIssuesAlone() {
        let line = Self.totals(Self.twoOfFour + ["✘ Test run with 4 tests in 1 suite failed after 0.020 seconds with 5 issues."])

        #expect(line == "totals: ✘ failed · Swift Testing 4 tests in 1 suite, 5 issues, 0 skipped")
    }

    /// Known issues come off both sides of the add-up check, and the issues figure is the tool's total less its known issues.
    @Test
    func knownIssuesComeOffBothSidesOfTheAddUp() {
        let lines = [
            "✘ Test boils() failed after 0.001 seconds with 3 issues (including 1 known issue).",
            "✔ Test countIsOne() passed after 0.001 seconds.",
            "✘ Test run with 2 tests in 1 suite failed after 0.020 seconds with 3 issues (including 1 known issue).",
        ]

        #expect(Self.totals(lines) == "totals: ✘ failed · Swift Testing 2 tests in 1 suite, 1 failing (2 issues), 0 skipped")
    }

    /// With no per-test failure line to read, the clause has only the issue count and says what it counts.
    @Test
    func withNoPerTestLineTheClauseNamesTheIssuesNeverFailures() {
        let line = Self.totals(["✘ Test run with 4 tests in 1 suite failed after 0.020 seconds with 4 issues."])

        #expect(line == "totals: ✘ failed · Swift Testing 4 tests in 1 suite, 4 issues")
    }

    /// XCTest's own counter counts recorded failures, and the failing tests come from its `Test Case … failed` lines.
    @Test
    func anXCTestCounterIsNamedRecordedFailuresBesideTheFailingTests() {
        let lines = [
            "Test Case '-[GizmoTests.PalletTests testOne]' failed (0.001 seconds).",
            "Test Case '-[GizmoTests.PalletTests testTwo]' passed (0.001 seconds).",
            "Executed 2 tests, with 3 failures (3 unexpected) in 0.002 (0.003) seconds",
        ]

        #expect(Self.totals(lines) == "totals: ✘ failed · XCTest 2 tests, 1 failing (3 recorded failures), 0 skipped")
    }

    /// The clause itself: nothing for no failures, the count under its unit with no per-test line, the failing count alone where the two agree.
    @Test
    func theClauseStatesEachCaseUnderItsUnit() {
        #expect(RunFailingTests.clause(failing: nil, recorded: 0, unit: "issue") == "")
        #expect(RunFailingTests.clause(failing: nil, recorded: 1, unit: "issue") == ", 1 issue")
        #expect(RunFailingTests.clause(failing: nil, recorded: 4, unit: "recorded failure") == ", 4 recorded failures")
        #expect(RunFailingTests.clause(failing: 3, recorded: 3, unit: "issue") == ", 3 failing")
        #expect(RunFailingTests.clause(failing: 2, recorded: 4, unit: "issue") == ", 2 failing (4 issues)")
    }

    /// A known issue leaves a test's failing line with fewer failures than the issues it states.
    @Test
    func aTestLinesKnownIssuesAreNotItsFailures() {
        #expect(RunFailingTests.netIssues(in: "✘ Test x() failed after 0.001 seconds with 3 issues (including 1 known issue).") == 2)
        #expect(RunFailingTests.netIssues(in: "✘ Test x() failed after 0.001 seconds with 1 issue.") == 1)
        #expect(RunFailingTests.netIssues(in: "✔ Test x() passed after 0.001 seconds.") == nil)
    }
}
