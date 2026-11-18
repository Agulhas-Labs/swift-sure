//
// Copyright © Agulhas Labs
//

import Foundation

/// The suite a failing Swift Testing test sits in, worked out from where the run printed it failing.
///
/// Swift Testing names a failure by its bare function, `testOne()`, with the file and line beside it and no suite at all. The suite is recoverable from those two: the index already knows which type encloses that line.
///
/// **A read of an existing index and nothing else.** The store is opened read-only through ``ReadOnlyIndex``: one at another schema version, missing or busy is skipped and left exactly as found, never dropped and rebuilt. No source is parsed and no index is built or freshened here: a repository that was never indexed, or a database this process cannot open, resolves nothing, and the name stays bare. A file name that more than one indexed file carries is not guessed at either, because a wrong suite recorded as a fact is worse than none.
struct FailureSuiteResolver {
    private let store: IndexStore
    private let reader: TestSymbolReader
    private let pathsByFileName: [String: [String]]

    /// The resolver over the index sitting under `repositoryRoot`, or `nil` where there is none or it cannot be read.
    init?(repositoryRoot: URL) {
        guard let store = ReadOnlyIndex.store(atRoot: repositoryRoot.path),
              let files = try? store.fileInventory()
        else {
            return nil
        }
        self.store = store
        reader = TestSymbolReader(store: store)
        pathsByFileName = Dictionary(grouping: files.keys) { ($0 as NSString).lastPathComponent }
    }

    /// The suite for the failure `name` printed at `location` (`File.swift:42:9`), nested types joined with `/` as XCTest spells them; `nil` where it cannot be said.
    ///
    /// The line must sit inside a function of that name: an `#expect` inside a helper that a test calls names the helper's type, which is not the test's suite.
    func suite(of name: String, atLocation location: String) -> String? {
        let parts = location.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let line = Int(parts[1]) else {
            return nil
        }
        let fileName = (String(parts[0]) as NSString).lastPathComponent
        guard let paths = pathsByFileName[fileName], paths.count == 1,
              let row = try? reader.enclosingSymbol(path: paths[0], line: line),
              let chain = try? store.parentChain(of: row)
        else {
            return nil
        }
        guard let function = (chain + [row]).last(where: { $0.kind == .function }),
              Self.baseName(function.name) == Self.baseName(name)
        else {
            return nil
        }
        let owners = (chain + [row]).filter(\.kind.isContainer)
        let names = QualifiedPath.flattened(chain: owners.map(\.name))
        return names.isEmpty ? nil : names.joined(separator: "/")
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
