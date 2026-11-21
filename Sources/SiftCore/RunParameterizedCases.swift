//
// Copyright © Agulhas Labs
//

import Foundation

/// How many test cases a run's parameterized Swift Testing tests ran, read from the `with N test cases` clause their ending lines carry.
struct RunParameterizedCases {
    /// The case count in the text after a test's name, as in ` with 4 test cases passed after 0.004 seconds.`, or `nil` for any other tail.
    static func count(in tail: Substring) -> Int? {
        guard tail.hasPrefix(" with "), let match = tail.prefixMatch(of: #/ with (\d+) test cases? (?:passed|failed) after /#) else {
            return nil
        }
        return Int(match.output.1)
    }

    /// The text that follows a test count when parameterized tests made the cases run outnumber the tests, ` (13 cases)`, and nothing where every test was one case, or where fewer distinct names ended in the log than the summary counts tests, since the console prints no suite and tests sharing a name were merged into one count.
    static func note(counts: [String: Int], tests: Int, named: Int) -> String {
        let extra = extraCases(counts: counts, tests: tests, named: named)
        return extra > 0 ? " (\(tests + extra) cases)" : ""
    }

    /// How many more cases than tests the parameterized tests ran, or zero where fewer distinct names ended in the log than `tests`, as in ``note(counts:tests:named:)``.
    static func extraCases(counts: [String: Int], tests: Int, named: Int) -> Int {
        guard named >= tests else {
            return 0
        }
        return counts.values.reduce(0) { $0 + max(0, $1 - 1) }
    }

    /// The clause a run of several Swift Testing tallies that are not summed carries when parameterized tests made the cases outnumber the tests, `; 9 more cases than tests across them`, and nothing otherwise.
    ///
    /// The cases are the run's own and no tally's, since the log does not say which bundle ran which test, so the clause is said once for all of them, as the skipped clause is. `tests` is the sum of the tallies that could be read, which is all a count of the tests can then be.
    static func acrossTalliesNote(counts: [String: Int], tests: Int, named: Int) -> String {
        let extra = extraCases(counts: counts, tests: tests, named: named)
        return extra > 0 ? "; \(extra) more cases than tests across them" : ""
    }
}
