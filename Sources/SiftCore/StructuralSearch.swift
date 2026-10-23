//
// Copyright © Agulhas Labs
//

import Foundation

/// Runs a `StructuralQuery` across the repository's Swift files.
///
/// Reads the **working tree**, not the index, and so has no staleness axis at all: it parses what is on disk at the moment of the query. That is why the schema stores no bodies for this — storing them would buy nothing a re-parse doesn't already give, and would add an invalidation problem where there currently is none.
///
/// Affordable because parsing is the cheap part: tens of thousands of files parse in a second or two, so a whole-repo shape query costs a fraction of a second even on a large monorepo. Files are parsed in parallel and each tree is discarded as soon as its matches are collected.
struct StructuralSearch {
    let repoRoot: URL
    let enumerator: FileEnumerator
    /// Text a file must contain to be parsed at all, where the query cannot match a file without it; `nil` parses every candidate.
    var requiredText: String?

    /// Every declaration in the repo satisfying `query`, ordered by path then line, those a `name:` pattern matches whole ahead of the rest.
    ///
    /// An alternation of short words matches inside many longer names (`key` in every `CodingKeys`), so in path order the declarations a caller named would sit anywhere in the answer; putting whole matches first keeps every row and puts the named ones on the first page.
    func run(_ query: StructuralQuery) async -> Result {
        let candidates = enumerator.swiftFiles().filter(query.admitsPath)
        let scan = await Self.scan(paths: candidates, repoRoot: repoRoot, query: query, requiredText: requiredText)
        let ordered = scan.matches.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
        let whole = ordered.filter { query.matchesNameWhole($0.qualifiedName) }
        return Result(
            matches: whole + ordered.filter { !query.matchesNameWhole($0.qualifiedName) },
            filesScanned: candidates.count,
            eliminations: scan.eliminations,
            wholeNameMatches: whole.count,
            filesParsed: scan.filesParsed
        )
    }

    private static func scan(paths: [String], repoRoot: URL, query: StructuralQuery, requiredText: String?) async -> Scanned {
        guard !paths.isEmpty else { return Scanned() }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let rootPath = repoRoot.path
        var total = Scanned()
        await withTaskGroup(of: Scanned.self) { group in
            var iterator = paths.makeIterator()
            var inFlight = 0
            while inFlight < cores, let path = iterator.next() {
                group.addTask { scanned(at: path, rootPath: rootPath, query: query, requiredText: requiredText) }
                inFlight += 1
            }
            for await found in group {
                total.matches.append(contentsOf: found.matches)
                total.eliminations.merge(found.eliminations, uniquingKeysWith: +)
                total.filesParsed += found.filesParsed
                if let path = iterator.next() {
                    group.addTask { scanned(at: path, rootPath: rootPath, query: query, requiredText: requiredText) }
                }
            }
        }
        return total
    }

    /// One file's matches and eliminations; an unreadable or non-UTF-8 file, or one whose bytes lack `requiredText`, contributes none and is not parsed.
    private static func scanned(at path: String, rootPath: String, query: StructuralQuery, requiredText: String?) -> Scanned {
        guard let data = FileManager.default.contents(atPath: rootPath + "/" + path) else {
            return Scanned()
        }
        if let requiredText, data.range(of: Data(requiredText.utf8)) == nil {
            return Scanned()
        }
        guard let source = String(data: data, encoding: .utf8) else {
            return Scanned()
        }
        let found = StructuralMatcher.scan(source, path: path, query: query)
        return Scanned(matches: found.matches, eliminations: found.eliminations, filesParsed: 1)
    }
}

extension StructuralSearch {
    /// What a scan of some files found, and how many of them it parsed.
    fileprivate struct Scanned {
        var matches: [StructuralMatch] = []
        var eliminations: [Int: Int] = [:]
        var filesParsed = 0
    }

    /// The matches plus the denominator they were drawn from — a count of zero means something different against 12 files than against 7,000.
    struct Result {
        let matches: [StructuralMatch]
        let filesScanned: Int
        /// For each position in the query's applied order, how many declarations that term was the first to reject; empty where no declaration reached the terms.
        var eliminations: [Int: Int] = [:]
        /// How many of the leading matches a `name:` pattern matched whole; the rest it matched only in part.
        var wholeNameMatches = 0
        /// How many files were parsed; a file skipped for lacking the required text, or unreadable, is not counted.
        var filesParsed = 0
    }
}
