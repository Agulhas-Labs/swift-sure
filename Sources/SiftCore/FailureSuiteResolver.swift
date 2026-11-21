//
// Copyright © Agulhas Labs
//

import Foundation

/// The suite a failing Swift Testing test sits in, worked out from where the run printed it failing.
///
/// Swift Testing names a failure by its bare function, `testOne()`, with the file and line beside it and no suite at all. The suite is recoverable from those two: the index already knows which type encloses that line.
///
/// **A read of an existing index and nothing else.** The store is opened read-only through ``ReadOnlyIndex``: one at another schema version, missing or busy is skipped and left exactly as found, never dropped and rebuilt. No index is built or freshened here and the store is never written (a file edited since indexing is parsed in memory for its one line): a repository that was never indexed, or a database this process cannot open, resolves nothing, and the name stays bare. A file name that more than one indexed file carries is not guessed at either, because a wrong suite recorded as a fact is worse than none.
struct FailureSuiteResolver {
    private let store: IndexStore
    private let reader: TestSymbolReader
    private let pathsByFileName: [String: [String]]
    private let files: [String: FileRow]
    private let repositoryRoot: URL
    private let parse: (URL, String) -> ParsedFile?
    private let reads = ReadCache()

    /// The resolver over the index sitting under `repositoryRoot`, or `nil` where there is none or it cannot be read.
    ///
    /// `parse` reads a file that changed since indexing; tests count its calls.
    init?(repositoryRoot: URL, parse: @escaping (URL, String) -> ParsedFile? = { FileParser.parse(absoluteURL: $0, repoRelativePath: $1) }) {
        guard let store = ReadOnlyIndex.store(atRoot: repositoryRoot.path),
              let files = try? store.fileInventory()
        else {
            return nil
        }
        self.store = store
        reader = TestSymbolReader(store: store)
        self.files = files
        self.repositoryRoot = repositoryRoot
        self.parse = parse
        pathsByFileName = Dictionary(grouping: files.keys) { ($0 as NSString).lastPathComponent }
    }

    /// The suite for the failure `name` printed at `location` (`File.swift:42:9`), nested types joined with `/` as XCTest spells them; `nil` where it cannot be said.
    ///
    /// The line must sit inside a function of that name: an `#expect` inside a helper that a test calls names the helper's type, which is not the test's suite.
    ///
    /// The stored rows are trusted only for a file whose size and change time still match its indexed row: after an edit the line can sit in another suite of the same file, so a changed file is parsed afresh, in memory, and a file that cannot be read or parsed says nothing.
    func suite(of name: String, atLocation location: String) -> String? {
        let parts = location.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let line = Int(parts[1]) else {
            return nil
        }
        let fileName = (String(parts[0]) as NSString).lastPathComponent
        guard let paths = pathsByFileName[fileName], paths.count == 1,
              let found = function(inFile: paths[0], line: line),
              Self.baseName(found.function) == Self.baseName(name)
        else {
            return nil
        }
        let names = QualifiedPath.flattened(chain: found.owners)
        return names.isEmpty ? nil : names.joined(separator: "/")
    }

    /// The function around `line` and its container names: from the stored rows while the file is unchanged since indexing, else from a fresh in-memory parse of the file.
    private func function(inFile path: String, line: Int) -> (function: String, owners: [String])? {
        let source: Source
        if let known = reads.sources[path] {
            source = known
        } else {
            source = isUnchangedSinceIndexed(path) ? .indexed : .fresh(parse(repositoryRoot.appendingPathComponent(path), path))
            reads.sources[path] = source
        }
        if case let .fresh(parsed) = source {
            return parsed.flatMap { FreshFailureScope.of(line: line, in: $0) }
        }
        guard let row = try? reader.enclosingSymbol(path: path, line: line),
              let chain = try? store.parentChain(of: row),
              let function = (chain + [row]).last(where: { $0.kind == .function })
        else {
            return nil
        }
        return (function.name, (chain + [row]).filter(\.kind.isContainer).map(\.name))
    }

    /// Whether the file at `path` still has the size and change time its index row recorded.
    private func isUnchangedSinceIndexed(_ path: String) -> Bool {
        guard let row = files[path],
              let stat = FileChangeStat.of(path: repositoryRoot.appendingPathComponent(path).path)
        else {
            return false
        }
        // The tolerance the indexer's own freshness check uses.
        return stat.size == row.size && Swift.abs(stat.changed - row.mtime) < 0.0001
    }

    private static func baseName(_ name: String) -> String {
        String(name.prefix { $0 != "(" })
    }

    /// The suite of each named failure whose location resolves, keyed by name; Swift Testing's bare names only, since an XCTest name carries its suite already.
    ///
    /// A name whose located failures resolve to more than one distinct suite is left out: one suite recorded for it would hide the others.
    static func suites(of failures: [RunTestFailure], repositoryRoot: URL?) -> [String: String] {
        guard !failures.isEmpty, let repositoryRoot, let resolver = FailureSuiteResolver(repositoryRoot: repositoryRoot) else {
            return [:]
        }
        var found: [String: Set<String>] = [:]
        for failure in failures where !failure.name.contains("/") {
            if let location = failure.location, let suite = resolver.suite(of: failure.name, atLocation: location) {
                found[failure.name, default: []].insert(suite)
            }
        }
        return found.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}

private extension FailureSuiteResolver {
    /// What one path resolves from, settled once per resolver.
    ///
    /// The stored rows, or the symbols of one fresh parse (`nil` where the file cannot be read or parsed). Symbols only; no syntax tree is kept.
    enum Source {
        case indexed
        case fresh(ParsedFile?)
    }

    /// The per-path decisions of one resolver, which lives for one `suites(of:repositoryRoot:)` call.
    final class ReadCache {
        var sources: [String: Source] = [:]
    }
}
