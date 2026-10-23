//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// The record of each time the bundle's installer put a binary on this machine: one JSON line per install in `~/.swift-sure/deploys.jsonl`, written by `install.sh` and read by `swift-sure report --deploys`.
///
/// Read-only here. The installer writes it in shell, before any binary of this build runs, so there is no writer in Swift to share a format with; a line that does not parse is skipped, because a log appended to by another program is never trusted to be whole.
public struct DeployLog {
    /// `~/.swift-sure/deploys.jsonl`, under the state directory `environment` names.
    public static func standardFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        SiftPaths.home(environment: environment).appendingPathComponent("deploys.jsonl")
    }

    /// The installs in `data`, in the order they were written, which is oldest first; a line that is not valid UTF-8, or not a JSON object with a `ts`, is left out.
    ///
    /// The bytes are split on newlines before anything is decoded, so one damaged line costs that line and not the file.
    static func entries(in data: Data) -> [Entry] {
        data.split(separator: UInt8(ascii: "\n")).compactMap { bytes in
            guard String(data: Data(bytes), encoding: .utf8) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
                  let time = object["ts"] as? String
            else { return nil }
            return Entry(
                time: time,
                version: object["version"] as? String,
                commit: object["commit"] as? String,
                sourceTree: object["sourceTree"] as? String,
                writtenWithSourceTree: object.keys.contains("sourceTree"),
                tree: object["tree"] as? String,
                binarySize: object["binarySize"] as? Int
            )
        }
    }

    /// The page `swift-sure report --deploys` prints: one line per install, newest last, in the columns time, build, version, tree state, size.
    ///
    /// The build column is `commit <sha>` for a release and `tree <hash>` for a local build, with `(commit <sha>)` after a tree the repository enclosing the current directory has a commit for. A line from before the log named the two apart holds one value that was either, so it is looked up as a tree and printed bare when no commit has it. A field the installer could not name reads `unknown`. A log with no installs says so rather than printing nothing.
    ///
    /// `trees` is asked at most once per page, and only when a row has a tree to look up.
    public static func render(fileURL: URL, trees: () -> [(commit: String, tree: String)] = enclosingTreeCommits) -> String {
        let rows = entries(in: (try? Data(contentsOf: fileURL)) ?? Data())
        guard !rows.isEmpty else { return "no deploys recorded: install.sh appends to deploys.jsonl in the state directory on each install" }
        var known: [(commit: String, tree: String)]?
        func commit(ofTree tree: String) -> String? {
            if known == nil {
                known = trees()
            }
            guard !tree.isEmpty else { return nil }
            return known?.first { $0.tree.hasPrefix(tree) }?.commit
        }
        return rows.map { row in
            [
                row.time,
                build(of: row, commitOfTree: commit(ofTree:)),
                row.version ?? "unknown",
                row.tree ?? "unknown",
                row.binarySize.map { String(format: "%.1f MB", Double($0) / 1_000_000) } ?? "unknown",
            ].joined(separator: "  ")
        }.joined(separator: "\n")
    }

    /// The commits of the repository enclosing the current directory with their trees, or none outside a repository or where git fails.
    public static func enclosingTreeCommits() -> [(commit: String, tree: String)] {
        treeCommits(enclosing: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    /// ``enclosingTreeCommits()`` for the repository enclosing `directory`.
    static func treeCommits(enclosing directory: URL) -> [(commit: String, tree: String)] {
        guard let root = GitContext.spawnedRoot(from: directory) else { return [] }
        return GitContext(repoRoot: root).commitTrees(limit: 5000) ?? []
    }

    private static func build(of row: Entry, commitOfTree: (String) -> String?) -> String {
        func tree(_ hash: String) -> String {
            commitOfTree(hash).map { "tree \(hash) (commit \($0))" } ?? "tree \(hash)"
        }
        if let hash = row.sourceTree {
            return tree(hash)
        }
        guard let value = row.commit else { return "unknown" }
        if row.writtenWithSourceTree {
            return "commit \(value)"
        }
        return commitOfTree(value) == nil ? value : tree(value)
    }
}

extension DeployLog {
    /// One install: any field the installer could not learn is `nil`.
    struct Entry: Equatable {
        var time: String
        var version: String?
        var commit: String?
        var sourceTree: String?
        /// Whether the line has a `sourceTree` key at all, null or not: a line without one predates the key, and its `commit` is a commit or a tree.
        var writtenWithSourceTree = false
        var tree: String?
        var binarySize: Int?
    }
}
