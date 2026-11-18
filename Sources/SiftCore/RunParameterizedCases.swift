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
        guard named >= tests else {
            return ""
        }
        let extra = counts.values.reduce(0) { $0 + max(0, $1 - 1) }
        return extra > 0 ? " (\(tests + extra) cases)" : ""
    }
}
