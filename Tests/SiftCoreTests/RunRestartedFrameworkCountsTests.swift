//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A restarted bundle's counts split a framework's tests into the passes around the restart only for the framework that restarted, and count what failed before it.
struct RunRestartedFrameworkCountsTests {
    private static var marker: String {
        "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
    }

    private static func totals(_ lines: [String]) -> String {
        var filter = RunOutputFilter(invokedAs: ["xcodebuild", "test"])
        for line in lines {
            filter.consume(line: line)
        }
        return totals(of: filter.finish(exitCode: 65))
    }

    private static func totals(of report: RunReport) -> String {
        let answer = RunReportRenderer(kind: .xcodebuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Depot"))
            .render(report, exitCode: 65, logURL: nil)
        return answer.split(separator: "\n").first { $0.hasPrefix("totals:") }.map(String.init) ?? ""
    }

    private static func capturedTotals() throws -> String {
        try totals(of: TestSources.runReport("xcodebuild-crash-restart", invokedAs: ["xcodebuild", "test"], exitCode: 65))
    }

    @Test
    func anXCTestRestartLeavesSwiftTestingUnsplit() throws {
        let totals = try Self.capturedTotals()

        #expect(totals.contains("Swift Testing 7 tests in 2 suites"))
        #expect(!totals.contains("Swift Testing 7 tests in 2 suites after"))
    }

    @Test
    func theXCTestCountNamesTheRelaunchedPassAndTheOneBeforeIt() throws {
        let totals = try Self.capturedTotals()

        #expect(totals.contains("XCTest 5 tests after the restart, 3 before it"))
    }

    @Test
    func aTestFailingBeforeAnXCTestRestartIsCountedFailing() {
        let totals = Self.totals([
            "Test Case '-[Gizmo.WidgetTests testOne]' started.",
            "Test Case '-[Gizmo.WidgetTests testOne]' failed (0.001 seconds).",
            "Test Case '-[Gizmo.WidgetTests testTwo]' started.",
            "", Self.marker, "",
            "Test Case '-[Gizmo.WidgetTests testThree]' started.",
            "Test Case '-[Gizmo.WidgetTests testThree]' passed (0.001 seconds).",
            "\t Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.002) seconds",
            "** TEST FAILED **",
        ])

        #expect(totals.contains("XCTest 1 test after the restart, 1 before it, 1 failing"))
    }

    @Test
    func aTestFailingBeforeASwiftTestingRestartIsCountedFailing() {
        let totals = Self.totals([
            "◇ Test run started.",
            "◇ Test one() started.", "✘ Test one() failed after 0.001 seconds with 1 issue.",
            "◇ Test two() started.",
            "", Self.marker, "",
            "◇ Test run started.",
            "◇ Test three() started.", "✔ Test three() passed after 0.001 seconds.",
            "✔ Test run with 1 test in 1 suite passed after 0.5 seconds.",
            "** TEST FAILED **",
        ])

        #expect(totals.contains("Swift Testing 1 test in 1 suite after the restart, 1 before it, 1 failing"))
    }
}
