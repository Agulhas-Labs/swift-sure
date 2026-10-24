//
// Copyright © Agulhas Labs
//

import Foundation

/// Scores the repository's declarations against one subject's syntactic shape: the engine under the `PostToolUse` reuse nudge.
///
/// Reads the **working tree**, not the index (Docs/Design.md §3): the axes it compares — a body's calls, its control flow, its written types — are not stored, and storing them would buy nothing a re-parse does not already give.
///
/// Every file is parsed once, its fingerprints extracted inside that call, and its tree dropped there — the rule that no syntax tree survives its file, kept at the only place where one exists.
struct SimilarSearch {
    /// The hits for `subject`, closest first and capped, or none when its body is too thin to compare.
    static func rank(subject: DeclarationFingerprint, among fingerprints: [DeclarationFingerprint]) -> [SimilarHit] {
        guard subject.callees.count >= SimilarityScore.minimumCallees else { return [] }
        let rarity = CalleeRarity(fingerprints: fingerprints)
        let cleared = fingerprints
            .lazy
            // A candidate sharing no callee has an overlap of zero, under any floor, so it is dropped before the full score is paid for.
            .filter { !$0.callees.isDisjoint(with: subject.callees) && !$0.isSameDeclaration(as: subject) }
            .map { SimilarityScore.hit(for: $0, against: subject, rarity: rarity) }
            .filter { $0.calleeOverlap >= SimilarityScore.calleeFloor }
            .sorted { left, right in
                // Score first, then path and line: a tie between two equally close shapes must land the same way on every run.
                guard left.score == right.score else { return left.score > right.score }
                return (left.fingerprint.declaration.path, left.fingerprint.declaration.line)
                    < (right.fingerprint.declaration.path, right.fingerprint.declaration.line)
            }
        return Array(cleared.prefix(SimilarityScore.resultCap))
    }

    /// Every file's fingerprints, parsed in parallel and ordered by path then line.
    static func scan(paths: [String], repoRoot: URL) async -> [DeclarationFingerprint] {
        guard !paths.isEmpty else { return [] }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let rootPath = repoRoot.path
        var collected: [DeclarationFingerprint] = []
        await withTaskGroup(of: [DeclarationFingerprint].self) { group in
            var iterator = paths.makeIterator()
            var inFlight = 0
            while inFlight < cores, let path = iterator.next() {
                group.addTask { fingerprints(at: path, rootPath: rootPath) }
                inFlight += 1
            }
            for await found in group {
                collected.append(contentsOf: found)
                if let path = iterator.next() {
                    group.addTask { fingerprints(at: path, rootPath: rootPath) }
                }
            }
        }
        return collected.sorted { ($0.declaration.path, $0.declaration.line) < ($1.declaration.path, $1.declaration.line) }
    }

    /// One file's fingerprints; an unreadable or non-UTF-8 file contributes none rather than failing the query.
    private static func fingerprints(at path: String, rootPath: String) -> [DeclarationFingerprint] {
        guard let data = FileManager.default.contents(atPath: rootPath + "/" + path),
              let source = String(data: data, encoding: .utf8) else { return [] }
        return FingerprintScanner.fingerprints(in: source, path: path)
    }
}
