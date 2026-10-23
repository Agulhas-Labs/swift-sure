//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A parameterised case's printed arguments are the test's text: a value that quotes a run's closing sentence is not the run's own.
///
/// The logs are fed to the filter as recorded text, never through `@Test(arguments:)`, whose values would put the same sentences into this suite's own log.
struct RunArgumentDescriptionTests {
    private static let preamble = [
        "Test Suite 'All tests' started at 2000-01-01 12:00:00.000.",
        "Test Suite 'All tests' passed at 2000-01-01 12:00:00.001.",
        "\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds",
        "◇ Test run started.",
        "◇ Test f(_:) started.",
    ]

    private static let closing = [
        "✔ Test f(_:) with 2 test cases passed after 0.001 seconds.",
        "✔ Test run with 1 test in 0 suites passed after 0.001 seconds.",
    ]

    private static func report(arguments: [String]) -> RunReport {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in preamble + arguments + closing {
            filter.consume(line: line)
        }
        return filter.finish(exitCode: 0)
    }

    /// Swift Testing's closing sentence and XCTest's count line quoted in an argument that breaks across lines.
    @Test
    func aQuotedClosingSentenceAndCountLineInAnArgumentAreNotTheRuns() {
        let report = Self.report(arguments: [
            "◇ Test case passing 1 argument text → \"before",
            "Executed 5 tests, with 0 failures (0 unexpected) in 0.100 (0.100) seconds",
            "✔ Test run with 4 tests in 1 suite passed after 0.001 seconds.",
            "after\" to f(_:) started.",
            "✔ Test case passing 1 argument text → \"before",
            "after\" to f(_:) passed after 0.001 seconds.",
        ])

        #expect(report.verdict?.state == .succeeded)
        #expect(report.tally?.tests == 1)
        #expect(report.summaryLines.count { $0.contains("Test run with") } == 1)
        #expect(!report.summaryLines.contains { $0.hasPrefix("Executed 5") })
    }

    /// An XCTest-shaped count line alone in an argument.
    @Test
    func aQuotedXCTestCountLineInAnArgumentIsNotTheRuns() {
        let report = Self.report(arguments: [
            "◇ Test case passing 1 argument text → \"",
            "Executed 5 tests, with 2 failures (0 unexpected) in 0.100 (0.100) seconds",
            "\" to f(_:) started.",
        ])

        #expect(report.verdict?.state == .succeeded)
        #expect(report.tally?.tests == 1)
        #expect(!report.summaryLines.contains { $0.hasPrefix("Executed 5") })
    }

    /// A case line cut short, its ending never printed, holds the lines after it only until the log ends, and they are read then, in order.
    @Test
    func aDescriptionWithNoEndingLosesNoLaterLine() {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in Self.preamble + [
            "◇ Test case passing 1 argument value → 2 to f(_:) started.",
            "◇ Test case passing 1 argument text → \"cut",
            "✘ Test g() recorded an issue at GizmoTests.swift:3:5: Expectation failed: false",
            "✘ Test g() failed after 0.001 seconds with 1 issue.",
            "✘ Test run with 2 tests in 0 suites failed after 0.001 seconds with 1 issue.",
        ] {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: 1)

        #expect(report.verdict?.state == .failed)
        #expect(report.tally?.tests == 2)
        #expect(report.testFailures.map(\.name) == ["g()"])
        #expect(report.testFailures.first?.location == "GizmoTests.swift:3:5")
    }

    /// A case opening whose ending never arrives holds back no later event: an issue whose argument breaks across lines after it is still joined, so its failure keeps its location and the count line inside it is not the run's.
    @Test
    func aStuckOpeningLeavesALaterIssueJoined() {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in Self.preamble + [
            "◇ Test g(_:) started.",
            "◇ Test case passing 1 argument text → \"cut",
            "✘ Test g(_:) recorded an issue with 1 argument text → \"one",
            "Executed 9 tests, with 0 failures (0 unexpected) in 0.100 (0.100) seconds",
            "✔ Test run with 99 tests in 9 suites passed after 1.000 seconds.",
            "two\" at GizmoTests.swift:7:5: Expectation failed: text.isEmpty",
            "✘ Test g(_:) with 1 test case failed after 0.001 seconds with 1 issue.",
            "✘ Test run with 2 tests in 0 suites failed after 0.001 seconds with 1 issue.",
        ] {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: 1)

        #expect(report.verdict?.state == .failed)
        #expect(report.tally?.tests == 2)
        #expect(!report.summaryLines.contains { $0.hasPrefix("Executed 9") })
        #expect(report.summaryLines.count { $0.contains("Test run with") } == 1)
        #expect(report.testFailures.map(\.name) == ["g(_:)"])
        #expect(report.testFailures.first?.location == "GizmoTests.swift:7:5")
    }

    /// A real closing line still reads, and a description that closes on its own line holds nothing back.
    @Test
    func aRealClosingLineStillReads() {
        let report = Self.report(arguments: [
            "◇ Test case passing 1 argument text → \"one line\" to f(_:) started.",
            "✔ Test case passing 1 argument text → \"one line\" to f(_:) passed after 0.001 seconds.",
        ])

        #expect(report.verdict?.state == .succeeded)
        #expect(report.tally?.tests == 1)
        #expect(report.summaryLines.contains { RunOutputFilter.undecorated($0).hasPrefix("Test run with 1 test in 0 suites passed") })
    }

    /// The real run behind the fixtures below, and its rendered answer: seven tests, five over strings holding an unescaped quote, a trailing backslash, a newline and two run-closing sentences, one over a type whose description holds one quote.
    private static func realRun(_ fixture: String, exitCode: Int32) throws -> (report: RunReport, answer: String) {
        let report = try TestSources.runReport(fixture, invokedAs: ["swift", "test"], exitCode: exitCode)
        let answer = RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"))
            .render(report, exitCode: exitCode, logURL: nil)
        return (report, answer)
    }

    /// A quote Swift Testing leaves unescaped in an argument holds nothing open: the passing run reads as passed, every test counted.
    @Test
    func anUnescapedQuoteInAnArgumentLeavesThePassingRunPassed() throws {
        let (report, answer) = try Self.realRun("swift-test-param-unescaped-pass", exitCode: 0)

        #expect(report.verdict?.state == .succeeded)
        #expect(report.tally?.tests == 7)
        #expect(answer.contains("totals: ✔ passed · Swift Testing 7 tests in 0 suites"))
    }

    /// An argument ending in a backslash, printed before a failing test, leaves that failure named.
    @Test
    func aTrailingBackslashInAnArgumentLeavesTheFailureAfterItNamed() throws {
        let (report, answer) = try Self.realRun("swift-test-param-unescaped-fail", exitCode: 1)

        #expect(report.verdict?.state == .failed)
        #expect(Set(report.testFailures.map(\.name)) == ["other()", "failingVerdict(_:)"])
        #expect(report.testFailures.first { $0.name == "other()" }?.location == "GizmoTests.swift:17:22")
        #expect(answer.contains("totals: ✘ failed · Swift Testing 7 tests in 0 suites, 2 failing, 0 skipped"))
    }

    /// Under `--verbose` a case names its argument's type before ` to`, and a description holding one quote still ends there, so every test is counted.
    @Test
    func aDescriptionHoldingOneQuoteUnderVerboseCountsEveryTest() throws {
        let (passed, passedAnswer) = try Self.realRun("swift-test-param-unescaped-pass-verbose", exitCode: 0)
        let (failed, failedAnswer) = try Self.realRun("swift-test-param-unescaped-fail-verbose", exitCode: 1)

        #expect(passed.verdict?.state == .succeeded)
        #expect(passed.tally?.tests == 7)
        #expect(passedAnswer.contains("totals: ✔ passed · Swift Testing 7 tests in 0 suites"))
        #expect(failed.verdict?.state == .failed)
        #expect(failed.tally?.tests == 7)
        #expect(failedAnswer.contains("totals: ✘ failed · Swift Testing 7 tests in 0 suites, 2 failing, 0 skipped"))
    }

    /// An issue line that prints a run's closing sentence inside its argument adds no count of its own, and the failure keeps its location and message.
    @Test
    func anIssueLinesArgumentAddsNothingToTheCount() throws {
        let (report, answer) = try Self.realRun("swift-test-param-unescaped-fail-verbose", exitCode: 1)
        let failure = try #require(report.testFailures.first { $0.name == "failingVerdict(_:)" })

        #expect(report.summaryLines.count { $0.contains("Test run with") } == 1)
        #expect(!answer.contains("bundles"))
        #expect(failure.location == "GizmoTests.swift:18:71")
        #expect(failure.message == "Expectation failed: !failing || text.isEmpty")
        #expect(failure.arguments?.hasPrefix(#"text → "before\n"#) == true)
    }
}
