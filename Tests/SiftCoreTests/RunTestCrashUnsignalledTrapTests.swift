//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A trap inside the stretch of a test the log left unfinished is quoted even where the run shows no signal line, and identical trap lines collapse to one with a count.
struct RunTestCrashUnsignalledTrapTests {
    private static var trap: String {
        "Tests/Foo.swift:7: Fatal error: x"
    }

    private static var signalLine: String {
        "error: Process '/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path /Users/dev/Pallet/.build/out/Products/Debug/PalletTests.xctest --testing-library swift-testing' exited with unexpected signal code 5"
    }

    /// Five identical traps inside the unfinished test's stretch, exit 1, no signal line: one counted line, ahead of the ended-without-a-result line.
    @Test
    func aTrapInsideTheUnfinishedTestIsQuotedOnceWithItsCount() {
        let report = Self.report(
            ["◇ Test run started.", "◇ Test topples() started."] + Array(repeating: Self.trap, count: 5),
            exitCode: 1
        )

        let lines = Self.answer(report).split(separator: "\n").map(String.init)

        #expect(lines.dropFirst().first == "  Tests/Foo.swift:7: Fatal error: x (×5)")
        #expect(lines.dropFirst(2).first == "  test process ended without a result (no signal line; swift test exited 1); started and never finished: topples()")
    }

    /// The same trap line printed by a test that went on to pass, ahead of another test's start, is that test's text and is not quoted.
    @Test
    func aTrapPrintedByATestThatFinishedIsNotQuoted() {
        let report = Self.report(
            [
                "◇ Test run started.",
                "◇ Test prints() started.",
                Self.trap,
                "✔ Test prints() passed after 0.001 seconds.",
                "◇ Test topples() started.",
            ],
            exitCode: 1
        )

        #expect(report.testCrash?.unfinished == ["topples()"])
        #expect(report.testCrash?.traps == [])
        #expect(!Self.answer(report).contains("Fatal error"))
    }

    /// A trap inside the unfinished test's stretch followed by another test passing in the same run is not a trap that ended the process, so it is not quoted.
    @Test
    func aTrapFollowedByATestEndingInTheSameRunIsNotQuoted() {
        let report = Self.report(
            [
                "◇ Test run started.",
                "◇ Test stacks() started.",
                "◇ Test topples() started.",
                Self.trap,
                "✔ Test stacks() passed after 0.001 seconds.",
            ],
            exitCode: 1
        )

        #expect(report.testCrash?.unfinished == ["topples()"])
        #expect(report.testCrash?.traps == [])
    }

    /// On the signal path two identical traps are one line with ` (×2)`.
    @Test
    func identicalTrapsOnTheSignalPathCollapseWithACount() {
        let report = Self.report(
            ["◇ Test run started.", "◇ Test topples() started.", Self.trap, Self.trap, Self.signalLine],
            exitCode: 1
        )

        let lines = Self.answer(report).split(separator: "\n").map(String.init)

        #expect(lines.filter { $0.contains("Fatal error") } == ["  Tests/Foo.swift:7: Fatal error: x (×2)"])
    }

    private static func report(_ lines: [String], exitCode: Int32) -> RunReport {
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        for line in lines {
            filter.consume(line: line)
        }
        return filter.finish(exitCode: exitCode)
    }

    private static func answer(_ report: RunReport) -> String {
        RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Pallet")).render(report, exitCode: 1, logURL: nil)
    }
}
