//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// The answer to `swift-sure flakes <query>`: the tests whose recorded name contains the query, each with the populations it was recorded failing in.
struct FlakesQueryAnswer {
    /// The most tests one answer prints, past which it says how many it left out.
    static let cap = 10

    /// The answer's lines, before the `log:` line, or `nil` when no run recorded which tests failed and none named a match anyway, so the ordinary empty state should speak.
    static func lines(for query: String, in named: RunFailureHistory.NamedFailures, scoped: String) -> [String]? {
        guard named.measured > 0 else {
            guard named.incompleteNaming + named.conflatedNaming + named.crashedMatching.count > 0 || !suiteLines(query, named).isEmpty else {
                return nil
            }
            return ["`\(query)` — no counted run recorded a matching test failing\(scoped)"] + crashOnlyLines(named, []) + uncountedLines(named) + suiteLines(query, named)
        }
        let over = "over \(counted(named.measured, "run")) that recorded which tests failed"
        let uncounted = uncountedLines(named)
        guard !named.tests.isEmpty else {
            let who = uncounted.isEmpty ? "no run" : "no counted run"
            return ["`\(query)` — \(who) recorded a matching test failing\(scoped), \(over)"] + crashOnlyLines(named, []) + uncounted + suiteLines(query, named)
        }
        var lines = ["`\(query)` — \(counted(named.tests.count, "test")) recorded failing\(scoped), \(over)"]
        for test in named.tests.prefix(cap) {
            lines.append(test.name)
            if let crash = named.crashedMatching.first(where: { $0.name == test.name }) {
                lines.append(crashLine(crash))
            }
            for population in test.populations {
                lines.append("  \(population.keys.joined(separator: ", ")) — failed \(population.failed) of \(counted(population.runs, "run")) · last \(population.lastFailed) · \(tail(population.tier))\(elsewhere(population))")
            }
        }
        lines += crashOnlyLines(named, named.tests.map(\.name))
        if named.tests.count > cap {
            lines.append("… and \(named.tests.count - cap) more tests match — narrow the query")
        }
        return lines + uncounted + suiteLines(query, named)
    }

    /// The one line saying a suite query could not reach Swift Testing failures recorded without a suite.
    ///
    /// Only for a query that reads as a suite or `Suite.member`: one starting with an uppercase letter, or carrying a `.` or `/`. A lowercase bare word or one carrying a `(` names a function, which a bare recorded name always matches. The count is of distinct suiteless test names, not of failures, and includes the names crash records list (crash records never carry a suite). Swift Testing records its failures by bare function name, and the suite is filed beside them only where the run could resolve it, so a record from before that or an unresolved one is invisible to a query by suite, and silence there would read as "never failed".
    private static func suiteLines(_ query: String, _ named: RunFailureHistory.NamedFailures) -> [String] {
        let readsAsSuite = query.first?.isUppercase == true || query.contains(".") || query.contains("/")
        guard named.suiteless > 0, readsAsSuite, !query.contains("("), !Redactor.isTestToken(query) else {
            return []
        }
        return ["\(counted(named.suiteless, "test")) in scope \(named.suiteless == 1 ? "carries" : "carry") no suite (crash records never do; failures recorded before this version, or unresolved) and could not be matched by one"]
    }

    private static func crashLine(_ crash: RunFailureHistory.CrashedTest) -> String {
        "  crashed in \(counted(crash.runs, "run")) · last \(crash.lastCrashed)"
    }

    /// The matching tests a crash left unfinished that no run recorded failing, each with its one crash line.
    private static func crashOnlyLines(_ named: RunFailureHistory.NamedFailures, _ failing: [String]) -> [String] {
        named.crashedMatching.filter { !failing.contains($0.name) }.prefix(cap).flatMap { [$0.name, crashLine($0)] }
    }

    /// The runs the counts above leave out: those that name a match anyway, and those that could not say.
    private static func uncountedLines(_ named: RunFailureHistory.NamedFailures) -> [String] {
        var lines: [String] = []
        let naming = named.incompleteNaming + named.conflatedNaming
        if naming > 0 {
            var parts: [String] = []
            if named.incompleteNaming > 0 {
                parts.append("\(named.incompleteNaming) with names past the log's cap")
            }
            if named.conflatedNaming > 0 {
                parts.append("\(named.conflatedNaming) under a kind that names no action")
            }
            lines.append("also named failing by \(counted(naming, "run")) not counted above: \(parts.joined(separator: ", "))")
        }
        if named.crashedRuns > 0 {
            lines.append(RunFailureHistory.CrashedTest.line(runs: named.crashedRuns, in: named.crashedIn, pastCap: named.crashedPastCap))
        }
        let silent = named.unrecorded + named.incompleteSilent
        if silent > 0 {
            var parts: [String] = []
            if named.unrecorded > 0 {
                parts.append("\(named.unrecorded) recorded no test names")
            }
            if named.incompleteSilent > 0 {
                parts.append("\(named.incompleteSilent) withheld names past the cap")
            }
            lines.append("\(counted(silent, "run")) cannot say: \(parts.joined(separator: ", "))")
        }
        return lines
    }

    private static func elsewhere(_ population: RunFailureHistory.NamedFailures.Population) -> String {
        guard let other = population.elsewhere else {
            return ""
        }
        return "; also failed \(counted(other.failed, "time")) on trees or command lines it never passed on, last \(other.lastFailed)"
    }

    private static func tail(_ tier: RunFailureHistory.NamedFailures.Tier) -> String {
        switch tier {
        case let .sameTree(trees):
            "same tree: failed and passed on \(trees == 1 ? "one tree" : "\(trees) trees")"
        case .otherTrees:
            "only on trees or command lines it never passed on"
        case .treeUnknown:
            "tree unknown"
        case let .everyRun(onRecordedTrees):
            onRecordedTrees ? "failed in every run on recorded trees" : "tree unknown, failed in every run"
        }
    }

    private static func counted(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
