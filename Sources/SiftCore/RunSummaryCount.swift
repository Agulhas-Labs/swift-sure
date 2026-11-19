//
// Copyright © Agulhas Labs
//

import Foundation

/// What the test frameworks' own closing lines counted for a run, summed over its test processes.
///
/// The inventory check reads it to tell a pass line lost from a loaded run's output from a test that never ran: the framework counts its own tests, so a summary that passes and covers every declared test says the unreported one did run.
public struct RunSummaryCount: Sendable, Equatable {
    /// The tests the summaries counted.
    public let tests: Int
    /// Whether every summary passed: a Swift Testing run that passed, an XCTest counter with no failure.
    public let passed: Bool
    /// The framework or frameworks that printed them, as the inventory line names them.
    public let framework: String

    public init(tests: Int, passed: Bool, framework: String) {
        self.tests = tests
        self.passed = passed
        self.framework = framework
    }
}

public extension RunReport {
    /// The summaries' counts, or `nil` where the run printed none or one of its lines does not parse.
    ///
    /// Read from the lines the tally parsers already read (``RunTestTally/parse(_:)`` and the `Executed …` counter), and summed only here: the answer's own `totals:` line never sums them, but the inventory check needs one number to set against the declared count.
    var summaryCount: RunSummaryCount? {
        var tests = 0
        var passed = true
        var swiftTesting = false
        var xctest = false
        for line in summaryLines {
            let undecorated = RunOutputFilter.undecorated(line)
            if undecorated.hasPrefix("Test run with ") {
                guard let tally = RunTestTally.parse(String(undecorated)) else {
                    return nil
                }
                swiftTesting = true
                tests += tally.tests
                passed = passed && tally.passed
            } else if line.hasPrefix("Executed "), let counts = RunOutputFilter.ExecutedCounts(line: line) {
                xctest = true
                tests += counts.tests
                passed = passed && counts.failures == 0 && counts.unexpected == 0
            }
        }
        let framework: String? = switch (swiftTesting, xctest) {
        case (true, true): "Swift Testing's and XCTest's"
        case (true, false): "Swift Testing's"
        case (false, true): "XCTest's"
        case (false, false): nil
        }
        return framework.map { RunSummaryCount(tests: tests, passed: passed, framework: $0) }
    }
}
