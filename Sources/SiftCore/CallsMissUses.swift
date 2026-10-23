//
// Copyright © Agulhas Labs
//

import Foundation

/// The `uses:` query a `calls:` miss suggests, and the line that says so.
///
/// A property, a type or a case is used and never called, so `calls:` cannot find it.
struct CallsMissUses {
    let query: StructuralQuery
    let name: String

    /// The query with the eliminating `calls:` term written `uses:`, where a non-negated `calls:` removed the last declarations, `nil` where the miss is not of that shape.
    init?(missing original: StructuralQuery, eliminations: [Int: Int]) {
        guard let position = eliminations.keys.max() else { return nil }
        let order = original.appliedOrder
        guard order.indices.contains(position) else { return nil }
        let term = order[position]
        guard term.field == .calls, !term.negated else { return nil }
        let eliminating = term.spelled
        var replaced = false
        let pieces = original.terms.map { candidate -> String in
            guard !replaced, candidate.spelled == eliminating else { return candidate.spelled }
            replaced = true
            return "uses:\(term.value)"
        }
        guard let query = try? StructuralQuery(pieces.joined(separator: " ")) else { return nil }
        self.query = query
        name = term.value
    }

    /// `note` with the line a `calls:` miss carries joined under it, the uses scanned once; `note` itself where the miss is not of that shape.
    static func appending(to note: String?, for query: StructuralQuery, result: StructuralSearch.Result, repoRoot: URL, enumerator: FileEnumerator) async -> String? {
        guard result.matches.isEmpty, let uses = CallsMissUses(missing: query, eliminations: result.eliminations) else { return note }
        let found = await StructuralSearch(repoRoot: repoRoot, enumerator: enumerator).run(uses.query).matches.count
        guard let line = uses.line(found: found) else { return note }
        return note.map { $0 + "\n" + line } ?? line
    }

    /// The line a `calls:` miss carries: the count of declarations the `uses:` query finds, and the term to try.
    ///
    /// `nil` when none match, since uses cannot explain the miss.
    func line(found: Int) -> String? {
        guard found > 0 else { return nil }
        return "\(name) is used, not called, in \(found) \(found == 1 ? "declaration" : "declarations"): try uses:\(name)"
    }
}
