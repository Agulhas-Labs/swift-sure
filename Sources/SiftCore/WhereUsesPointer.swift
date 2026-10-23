//
// Copyright © Agulhas Labs
//

import Foundation

/// The line every `where` answer that finds no declaration of the name carries when the tree uses that written name: a name declared nowhere is often an SDK or dependency symbol, so the answer says it is used and which call lists the uses.
struct WhereUsesPointer {
    /// The pointers an absence answer carries for `name`: the basename pointer, then this one.
    static func absenceLines(for name: String, in store: IndexStore, at revision: String?, paths: [String], spelling: CallSpelling, usesFileCount: ((String) async -> Int)?) async throws -> [String] {
        let basename = try WhereBasenamePointer.lines(for: name, in: store, at: revision.map { WhereBasenamePointer.Revision(name: $0, paths: paths) }, spelling: spelling)
        guard let usesFileCount, !name.isEmpty, try store.symbols(named: name).isEmpty else {
            return basename
        }
        return await basename + lines(for: name, fileCount: usesFileCount(name), at: revision, spelling: spelling)
    }

    /// The pointer, or none where no file uses the name.
    ///
    /// Under a revision the line keeps the count and names no call, since `search` reads the working tree and has no revision to read.
    static func lines(for name: String, fileCount: Int, at revision: String?, spelling: CallSpelling) -> [String] {
        guard fileCount > 0 else {
            return []
        }
        let noun = fileCount == 1 ? "file" : "files"
        if let revision {
            return ["not declared at \(revision) (an SDK or dependency symbol?); used in \(fileCount) \(noun) there"]
        }
        return ["not declared in this tree (an SDK or dependency symbol?); used in \(fileCount) \(noun): \(spelling.searchUses(of: name))"]
    }

    /// The files whose code uses `name`, counted by the scan `search uses:` performs.
    static func fileCount(of name: String, repoRoot: URL, enumerator: FileEnumerator) async -> Int {
        await scan(of: name, repoRoot: repoRoot, enumerator: enumerator).files
    }

    /// The scan `search uses:` performs for `name`, parsing only the files whose bytes contain the name where those bytes are the query's.
    static func scan(of name: String, repoRoot: URL, enumerator: FileEnumerator) async -> Scan {
        guard let query = try? StructuralQuery("uses:\(name)") else {
            return Scan(files: 0, filesParsed: 0)
        }
        let result = await StructuralSearch(repoRoot: repoRoot, enumerator: enumerator, requiredText: requiredText(for: name, query: query)).run(query)
        return Scan(files: Set(result.matches.map(\.path)).count, filesParsed: result.filesParsed)
    }

    /// The bytes a file must contain to be parsed: the name where the query is that one `uses:` term, the name is ASCII without a `K` and the query reads it as written; otherwise `nil`, since the query reads a composed or decomposed character, `|` or whitespace differently from the file's bytes, and Swift's string equality takes U+212A KELVIN SIGN for `K`, the one non-ASCII scalar canonically equal to an ASCII letter.
    static func requiredText(for name: String, query: StructuralQuery) -> String? {
        guard query.terms.count == 1, let term = query.terms.first, term.field == .uses, !term.negated else {
            return nil
        }
        let readsAsWritten = name.utf8.allSatisfy { $0 < 0x80 } && !name.contains("K")
        return readsAsWritten && term.alternatives == [name] ? name : nil
    }
}

extension WhereUsesPointer {
    /// What a `uses:` scan for a name found and how many files it parsed to find it.
    struct Scan: Equatable {
        /// The files whose code uses the name.
        let files: Int
        /// The files the scan parsed, which the byte pre-filter keeps to those that can use the name.
        let filesParsed: Int
    }
}
