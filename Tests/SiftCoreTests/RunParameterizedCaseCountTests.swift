//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The `totals:` line says how many test cases ran where parameterized tests made them outnumber the tests, and prints nothing extra where they did not.
struct RunParameterizedCaseCountTests {
    private static func totals(of lines: [String], invokedAs arguments: [String], kind: RunCommandKind) -> String? {
        var filter = RunOutputFilter(invokedAs: arguments)
        for line in lines {
            filter.consume(line: line)
        }
        let report = filter.finish(exitCode: 0)
        let answer = RunReportRenderer(kind: kind, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"), selector: RunTestSelector.named(in: arguments))
            .render(report, exitCode: 0, logURL: nil)
        return answer.split(separator: "\n").map(String.init).first { $0.hasPrefix("totals:") }
    }

    /// One test over four sizes: the run's own sentence says one test, the test's ending line says four cases.
    @Test(arguments: [
        (["swift", "test"], RunCommandKind.swiftTest),
        (["xcodebuild", "test", "-scheme", "Gizmo"], RunCommandKind.xcodebuild),
    ])
    func oneParameterizedTestNamesItsCases(arguments: [String], kind: RunCommandKind) {
        let lines = [
            "◇ Test run started.",
            "◇ Suite DepotTests started.",
            "◇ Test sizeIsCarried(size:) started.",
            "◇ Test case passing 1 argument size → 1 to sizeIsCarried(size:) started.",
            "✔ Test sizeIsCarried(size:) with 4 test cases passed after 0.004 seconds.",
            "✔ Suite DepotTests passed after 0.005 seconds.",
            "✔ Test run with 1 test in 1 suite passed after 0.005 seconds.",
        ]
        let line = Self.totals(of: lines, invokedAs: arguments, kind: kind)

        #expect(line?.hasSuffix("Swift Testing 1 test (4 cases) in 1 suite, 0 skipped") == true, "\(line ?? "no totals line")")
    }

    /// Two parameterized tests (4 and 3 cases) among eight plain ones: ten tests, fifteen cases.
    @Test
    func severalParameterizedTestsSumBesidePlainOnes() {
        var lines = ["◇ Test run started.", "◇ Suite OrchardTests started."]
        lines.append("✔ Test pickedRows(count:) with 4 test cases passed after 0.001 seconds.")
        lines.append("✔ Test bushels(size:) with 3 test cases passed after 0.001 seconds.")
        for index in 1 ... 8 {
            lines.append("✔ Test plain\(index)() passed after 0.001 seconds.")
        }
        lines.append("✔ Suite OrchardTests passed after 0.010 seconds.")
        lines.append("✔ Test run with 10 tests in 1 suite passed after 0.010 seconds.")
        let line = Self.totals(of: lines, invokedAs: ["swift", "test"], kind: .swiftTest)

        #expect(line?.hasSuffix("Swift Testing 10 tests (15 cases) in 1 suite, 0 skipped") == true, "\(line ?? "no totals line")")
    }

    /// A run with no parameterized test, and one whose parameterized test has a single case, print the line they always printed.
    @Test
    func aRunWithoutExtraCasesPrintsNoCaseCount() {
        let lines = [
            "◇ Test run started.",
            "✔ Test onlyCase(_:) with 1 test case passed after 0.001 seconds.",
            "✔ Test plain() passed after 0.001 seconds.",
            "✔ Test run with 2 tests in 0 suites passed after 0.002 seconds.",
        ]
        let line = Self.totals(of: lines, invokedAs: ["swift", "test"], kind: .swiftTest)

        #expect(line == "totals: ✔ passed · Swift Testing 2 tests in 0 suites, 0 skipped")
    }

    /// Two suites each hold a `check(x:)` of three cases; the console names no suite, so the two cannot be told apart and a case total would be a guess.
    @Test
    func twoTestsSharingANameLeaveTheCaseCountOut() {
        let lines = [
            "◇ Test run started.",
            "✔ Test check(x:) with 3 test cases passed after 0.001 seconds.",
            "✔ Suite WidgetTests passed after 0.002 seconds.",
            "✔ Test check(x:) with 3 test cases passed after 0.001 seconds.",
            "✔ Suite DepotTests passed after 0.002 seconds.",
            "✔ Test run with 2 tests in 2 suites passed after 0.004 seconds.",
        ]
        let line = Self.totals(of: lines, invokedAs: ["swift", "test"], kind: .swiftTest)

        #expect(line == "totals: ✔ passed · Swift Testing 2 tests in 2 suites, 0 skipped")
    }

    /// A parameterized test that failed and passed on a retry is one test, so its note stays.
    @Test
    func aRetriedParameterizedTestKeepsItsNote() {
        let lines = [
            "◇ Test run started.",
            "◇ Test sizeIsCarried(size:) started.",
            "✘ Test sizeIsCarried(size:) with 4 test cases failed after 0.004 seconds with 1 issue.",
            "◇ Test sizeIsCarried(size:) started.",
            "✔ Test sizeIsCarried(size:) with 4 test cases passed after 0.004 seconds.",
            "✔ Test run with 1 test in 0 suites passed after 0.010 seconds.",
        ]
        let line = Self.totals(of: lines, invokedAs: ["swift", "test"], kind: .swiftTest)

        #expect(line?.contains("Swift Testing 1 test (4 cases) in 0 suites") == true, "\(line ?? "no totals line")")
    }
}
