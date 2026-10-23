//
// Copyright © Agulhas Labs
//

import Foundation
import SwiftSyntax

/// The working tree's uses of a name as a type, for an answer that waits on them: files are read several at once, a batch at a time, so the caller stops at the first batch whose uses settle its question.
///
/// Only a file writing the name as a whole word is parsed: a short or common name is a substring of almost every file (`T`, `Data` in `Metadata`), and a parse costs far more than the word check.
struct TypeUseScan {
    let repoRoot: URL
    let enumerator: FileEnumerator
    /// The uses of a name as a type in one file's source, given the source, its path and the name: the parse every candidate file takes, and the point a test counts them at.
    var sitesInSource: @Sendable (String, String, String) -> [SyntacticCallSite] = { source, path, name in
        NestingGate.parseOrEmpty(source) {
            CallSiteScanner.sites(in: $0, converter: SourceLocationConverter(fileName: path, tree: $0), path: path, names: [name: .typeUse]).sites[name] ?? []
        }
    }

    /// Whether `settles` holds for the uses of `name` as a type in some batch of the working tree's Swift files, batches taken in path order and each one's uses in path then line order.
    func settles(_ name: String, by settles: ([SyntacticCallSite]) throws -> Bool) throws -> Bool {
        let paths = enumerator.swiftFiles()
        let batchSize = max(1, ProcessInfo.processInfo.activeProcessorCount) * 8
        var start = 0
        while start < paths.count {
            let batch = Array(paths[start ..< min(start + batchSize, paths.count)])
            start += batchSize
            let sites = uses(of: name, in: batch)
            if !sites.isEmpty, try settles(sites) {
                return true
            }
        }
        return false
    }

    /// Whether `source` writes `name` with no ASCII letter, digit or underscore against either end of it; a non-ASCII neighbour counts as a boundary, so no file using the name is ever left out.
    static func writesWord(_ name: String, in source: String) -> Bool {
        guard !name.isEmpty else { return false }
        let bytes = source.utf8
        var from = source.startIndex
        while let found = source.range(of: name, options: .literal, range: from ..< source.endIndex) {
            let before = found.lowerBound > bytes.startIndex ? bytes[bytes.index(before: found.lowerBound)] : nil
            let after = found.upperBound < bytes.endIndex ? bytes[found.upperBound] : nil
            if !isIdentifierByte(before), !isIdentifierByte(after) {
                return true
            }
            from = source.unicodeScalars.index(after: found.lowerBound)
        }
        return false
    }

    private static func isIdentifierByte(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return switch byte {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "_"): true
        default: false
        }
    }

    /// The uses of `name` as a type in `paths`, the files read and parsed concurrently.
    private func uses(of name: String, in paths: [String]) -> [SyntacticCallSite] {
        let rootPath = repoRoot.path
        let found = FoundSites(count: paths.count)
        let parse = sitesInSource
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let path = paths[index]
            guard let data = FileManager.default.contents(atPath: rootPath + "/" + path),
                  let source = String(data: data, encoding: .utf8),
                  Self.writesWord(name, in: source) else { return }
            found.set(parse(source, path, name), at: index)
        }
        return found.joined()
    }
}

private extension TypeUseScan {
    /// One batch's sites by the index of the file they were found in, filled from several threads at once.
    final class FoundSites: @unchecked Sendable {
        private let lock = NSLock()
        private var byFile: [[SyntacticCallSite]]

        init(count: Int) {
            byFile = Array(repeating: [], count: count)
        }

        func set(_ sites: [SyntacticCallSite], at index: Int) {
            lock.withLock { byFile[index] = sites }
        }

        func joined() -> [SyntacticCallSite] {
            lock.withLock { byFile.flatMap(\.self) }
        }
    }
}
