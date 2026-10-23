//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A run whose test bundle `xcodebuild` restarted keeps the dead process's trap message in its answer, and counts the skips of the pass that died.
struct RunRestartedTrapAndSkipTests {
    private static var marker: String {
        "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
    }

    private static func answer(_ lines: [String], exitCode: Int32 = 65) -> String {
        var filter = RunOutputFilter(invokedAs: ["xcodebuild", "test"])
        for line in lines {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: exitCode)
        return RunReportRenderer(kind: .xcodebuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Depot"))
            .render(report, exitCode: exitCode, logURL: nil)
    }

    private static func xctest(_ method: String, _ ending: String) -> String {
        "Test Case '-[WidgetTests.WidgetTests \(method)]' \(ending)"
    }

    private static var trappedInMultiplies: [String] {
        [
            "◇ Test run started.",
            "◇ Test adds() started.",
            "Other/Look.swift:3: Fatal error: printed by a test that passed",
            "✔ Test adds() passed after 0.001 seconds.",
            "◇ Test multiplies() started.",
            "Calculator/Calc.swift:12: Fatal error: Index out of range",
            "", marker, "",
            "◇ Test run started.",
            "◇ Test divides() started.", "✔ Test divides() passed after 0.001 seconds.",
            "✔ Test run with 1 test in 1 suite passed after 1.000 seconds.",
            "** TEST FAILED **",
        ]
    }

    private static var skippedBeforeTheRestart: [String] {
        [
            xctest("testOne", "started."),
            xctest("testOne", "skipped (0.001 seconds)."),
            xctest("testTwo", "started."),
            marker,
            xctest("testThree", "started."),
            xctest("testThree", "passed (0.001 seconds)."),
            "Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.002) seconds",
            "** TEST FAILED **",
        ]
    }

    @Test
    func theTrapTheOpenTestPrintedBeforeTheRestartIsInTheAnswer() {
        let answer = Self.answer(Self.trappedInMultiplies)

        #expect(answer.contains("Calculator/Calc.swift:12: Fatal error: Index out of range"))
    }

    @Test
    func aTrapPrintedBeforeTheOpenTestStartedIsNotTheRestartsOwn() {
        let answer = Self.answer(Self.trappedInMultiplies)

        #expect(!answer.contains("Other/Look.swift:3"))
    }

    @Test
    func theCapturedCrashAndRestartKeepsItsTrapMessage() throws {
        let lines = try TestSources.runOutput("xcodebuild-crash-restart").components(separatedBy: "\n")

        let answer = Self.answer(lines)

        #expect(answer.contains("Fatal error: boom"))
    }

    @Test
    func anXCTestSkipBeforeTheRestartIsCountedOnTheTotalsLine() {
        let answer = Self.answer(Self.skippedBeforeTheRestart)
        let totals = answer.split(separator: "\n").first { $0.hasPrefix("totals:") }.map(String.init) ?? ""

        #expect(totals.hasSuffix("XCTest 1 test after the restart, 1 before it, 1 skipped"))
    }
}
