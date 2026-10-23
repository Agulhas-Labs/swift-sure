//
// Copyright © Agulhas Labs
//

import Foundation

/// How many tests failed, as against how many failures, issues or expectations the framework recorded, and the totals clause that states both under their own units.
///
/// A framework's own failure count is of recorded issues: a test with two failed expectations adds two to it. Printed beside the test count as a bare `failures`, it reads as a count of tests, so `4 tests, 4 failures` over two tests that each failed twice reads as every test failed. The clause here counts the tests, read from the per-test failure lines, and names the framework's own count by its unit where the two differ.
struct RunFailingTests {
    /// The clause for one framework's failures, with its leading `, `, or an empty string where it recorded none.
    ///
    /// `failing` is the count of failed tests where the per-test lines could be read, or `nil` where they could not; `recorded` is the framework's own count, named by `unit` in the singular (`issue`, `recorded failure`).
    static func clause(failing: Int?, recorded: Int, unit: String) -> String {
        guard recorded > 0 else {
            return ""
        }
        let own = "\(recorded) \(unit)\(recorded == 1 ? "" : "s")"
        guard let failing, failing > 0 else {
            return ", \(own)"
        }
        return failing == recorded ? ", \(failing) failing" : ", \(failing) failing (\(own))"
    }

    /// The Swift Testing clause for a run whose summaries recorded `issues` failures, net of known issues.
    ///
    /// The failing-test count is used only where the per-test issue counts add up to the summary's; a console that lost lines, or a test whose ending came from the event stream and states no count, leaves the issues alone.
    static func swiftTesting(issues: Int, outcomes: RunTestOutcomes) -> String {
        let failed = outcomes.swiftTestingNames.filter { outcomes.lastEndings[$0] == .failed }
        let perTest = failed.compactMap { outcomes.failureIssues[$0] }
        let addsUp = perTest.count == failed.count && perTest.reduce(0, +) == issues
        return clause(failing: addsUp ? failed.count : nil, recorded: issues, unit: "issue")
    }

    /// The XCTest clause for a counter that recorded `recorded` failures.
    static func xctest(recorded: Int, outcomes: RunTestOutcomes) -> String {
        let failed = outcomes.lastEndings.filter { $0.value == .failed && !outcomes.swiftTestingNames.contains($0.key) }
        return clause(failing: failed.isEmpty ? nil : failed.count, recorded: recorded, unit: "recorded failure")
    }

    /// The issues a Swift Testing test's failing line records, net of its known issues: `✘ Test x() failed after 0.001 seconds with 3 issues (including 1 known issue).` is 2.
    static func netIssues(in line: String) -> Int? {
        let pattern = #/ failed after [\d.]+ seconds? with (\d+) issues?(?: \(including (\d+) known issues?\))?\./#
        guard let match = line.firstMatch(of: pattern), let issues = Int(match.1) else {
            return nil
        }
        return max(0, issues - (match.2.flatMap { Int($0) } ?? 0))
    }
}
