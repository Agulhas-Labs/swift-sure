//
// Copyright © Agulhas Labs
//

import Foundation

/// The answer to `swift-sure flakes <query>`: the tests whose recorded name contains the query, each with the populations it was recorded failing in.
struct FlakesQueryAnswer {
    /// The most tests one answer prints, past which it says how many it left out.
    static let cap = 10

    /// The answer's lines, before the `log:` line, or `nil` when no run recorded which tests failed and none named a match anyway, so the ordinary empty state should speak.
    static func lines(for query: String, in named: RunFailureHistory.NamedFailures, scoped: String) -> [String]? {
        guard named.measured > 0 else {
            guard named.incompleteNaming + named.conflatedNaming > 0 else {
                return nil
            }
            return ["`\(query)` — no counted run recorded a matching test failing\(scoped)"] + uncountedLines(named)
        }
        let over = "over \(counted(named.measured, "run")) that recorded which tests failed"
        let uncounted = uncountedLines(named)
        guard !named.tests.isEmpty else {
            let who = uncounted.isEmpty ? "no run" : "no counted run"
            return ["`\(query)` — \(who) recorded a matching test failing\(scoped), \(over)"] + uncounted
        }
        var lines = ["`\(query)` — \(counted(named.tests.count, "test")) recorded failing\(scoped), \(over)"]
        for test in named.tests.prefix(cap) {
            lines.append(test.name)
            for population in test.populations {
                lines.append("  \(population.keys.joined(separator: ", ")) — failed \(population.failed) of \(counted(population.runs, "run")) · last \(population.lastFailed) · \(tail(population.tier))\(elsewhere(population))")
            }
        }
        if named.tests.count > cap {
            lines.append("… and \(named.tests.count - cap) more tests match — narrow the query")
        }
        return lines + uncounted
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
