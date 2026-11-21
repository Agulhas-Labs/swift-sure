//
// Copyright © Agulhas Labs
//

import Foundation

/// What a failure listing says once rather than again: the cases of one parameterized expectation, and an excerpt one test has already printed.
///
/// Both compare the failures of one test, never two, and both compare exactly: `the same` is a claim, so two excerpts that differ in a temporary directory's name are printed twice, and two messages that differ only in an error code are two groups.
///
/// **Cases of one expectation.** The cases of a parameterized test that fail at one location with one message are printed as one block, at the place the first of them was listed: the case first in argument order, so the block does not change with the order parallel cases finished in, then a line naming the others. A case read from the event stream is never grouped.
///
/// **The same excerpt.** A failure's excerpt is its note's lines beneath the first, without a trailing count of lines the note left out. A located failure whose excerpt runs to two lines or more, and is the excerpt printed under the nearest earlier listed failure of the same test or its first lines, prints one line pointing at that failure in its place; the note's first line stays, since it carries the expectation's own expression.
struct RunListingFolds {
    /// The failures the listing prints, in the order it prints them: every failure but a group's other cases.
    let listed: [Int]
    /// What a listed failure's entry says differently, keyed by its position.
    let folds: [Int: Fold]
}

extension RunListingFolds {
    /// How one listed failure's entry departs from the failure printed alone.
    struct Fold {
        /// How many failures the entry stands for: more than one where the printed case itself failed more than once at its location.
        var count = 1
        /// The line beneath a group's printed case naming its other cases, without its indent.
        var cases: String?
        /// The earlier listed failure whose printed excerpt this one's repeats.
        var repeated: Repeat?
        /// What the entry prints, unclipped, in place of its message line where a long message or value was printed above.
        var messageLine: String?
    }

    /// An excerpt printed above, which a later failure's excerpt equals or begins.
    struct Repeat {
        /// The position of the failure the excerpt was printed under.
        let position: Int
        /// How many lines this failure's own excerpt runs to.
        let lines: Int
    }

    /// The folds of `failures`, their cases put in argument order by `inArgumentOrder` and the place a listed failure's heading shows given by `placedAt`.
    static func of(_ failures: [RunFailureShape.Failure], inArgumentOrder: ([Int]) -> [Int], placedAt: (Int) -> String?) -> RunListingFolds {
        var members: [CaseKey: [Int]] = [:]
        for (position, failure) in failures.enumerated() {
            if let key = CaseKey(failure) {
                members[key, default: []].append(position)
            }
        }
        var listed: [Int] = []
        var folds: [Int: Fold] = [:]
        var placed: Set<CaseKey> = []
        for (position, failure) in failures.enumerated() {
            guard let key = CaseKey(failure), let group = members[key], Set(group.map { failures[$0].arguments }).count > 1 else {
                listed.append(position)
                continue
            }
            guard placed.insert(key).inserted else {
                continue
            }
            let lead = inArgumentOrder(group)[0]
            listed.append(lead)
            folds[lead] = grouped(group, under: lead, in: failures)
        }
        var printedExcerpt: [String: (index: Int, excerpt: [String])] = [:]
        for (index, position) in listed.enumerated() {
            let failure = failures[position]
            let excerpt = Self.excerpt(beneath: noteLines(of: failure).dropFirst())
            if failure.location != nil, excerpt.count > 1, let earlier = printedExcerpt[failure.name],
               failures[listed[earlier.index]].location != nil, Array(earlier.excerpt.prefix(excerpt.count)) == excerpt,
               let place = placedAt(listed[earlier.index]),
               !listed[(earlier.index + 1) ..< index].contains(where: { placedAt($0) == place })
            {
                folds[position, default: Fold()].repeated = Repeat(position: listed[earlier.index], lines: excerpt.count)
            } else if !excerpt.isEmpty {
                printedExcerpt[failure.name] = (index, excerpt)
            }
        }
        foldLongMessages(failures, listed: listed, folds: &folds, placedAt: placedAt)
        return RunListingFolds(listed: listed, folds: folds)
    }

    /// The lines a failure's entry prints beneath its note's first, with an excerpt printed above replaced by the line saying so and the note's count of left-out lines kept.
    static func printed(beneath lines: ArraySlice<String>, repeating location: String?, of repeated: Repeat?) -> [String] {
        guard let repeated, let location else {
            return Array(lines)
        }
        let said = "(the same \(repeated.lines) lines as under the failure at \(location) above)"
        return [said] + lines.dropFirst(repeated.lines)
    }
}

private extension RunListingFolds {
    /// What makes failures cases of one expectation: one test, one location, one message, word for word.
    struct CaseKey: Hashable {
        let name: String
        let location: String
        let message: String

        /// The key of a parameterized case with a location the run printed, or `nil` for any failure that is never grouped.
        init?(_ failure: RunFailureShape.Failure) {
            guard failure.arguments != nil, !failure.readFromStream, let location = failure.location else {
                return nil
            }
            name = failure.name
            self.location = location
            message = failure.message
        }
    }

    /// The fold of a group's printed case: its own repeats counted on its heading, and every other case named once beneath it.
    static func grouped(_ group: [Int], under lead: Int, in failures: [RunFailureShape.Failure]) -> Fold {
        let printed = failures[lead]
        var counts: [String: Int] = [:]
        for position in group where failures[position].arguments != printed.arguments {
            counts[failures[position].arguments ?? "", default: 0] += 1
        }
        let named = counts.keys.sorted().map { arguments in
            RunFailureCensus.clipped(arguments) + (counts[arguments, default: 0] > 1 ? " ×\(counts[arguments, default: 0])" : "")
        }
        let differ = group.contains { failures[$0].note != printed.note || failures[$0].closestLine != printed.closestLine } ? " (their values differ — see the raw log)" : ""
        let noun = named.count == 1 ? "case" : "cases"
        let line = "… and \(named.count) more \(noun) of this expectation: \(RunFailureCensus.clipped(named.joined(separator: ", ")))\(differ)"
        return Fold(count: group.count { failures[$0].arguments == printed.arguments }, cases: line)
    }

    /// A failure's note, one entry per line it printed.
    static func noteLines(of failure: RunFailureShape.Failure) -> [String] {
        failure.note.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) } ?? []
    }

    /// The excerpt among `lines`, which are a note's lines beneath its first: all of them but a trailing count of lines the note left out.
    static func excerpt(beneath lines: ArraySlice<String>) -> [String] {
        guard let last = lines.last, last.hasPrefix("… (+"), last.hasSuffix(" more lines — see the raw log)") else {
            return Array(lines)
        }
        return Array(lines.dropLast())
    }
}
