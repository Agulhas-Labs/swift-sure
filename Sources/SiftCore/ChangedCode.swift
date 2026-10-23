//
// Copyright © Agulhas Labs
//

import Foundation

/// What the working tree changed against a revision: the declarations it touched and every after-side line it added or rewrote, whether or not a declaration holds that line.
public struct ChangedCode: Sendable, Equatable {
    /// The changed declarations, in path and line order.
    public let declarations: [ChangedDeclaration]
    /// Each changed file's after-side line numbers (1-based) the diff adds or rewrites, keyed by repository-relative path.
    public let lines: [String: Set<Int>]

    public init(declarations: [ChangedDeclaration], lines: [String: Set<Int>]) {
        self.declarations = declarations
        self.lines = lines
    }

    /// Every path the change touched, sorted.
    public var paths: [String] {
        Array(Set(declarations.map(\.path)).union(lines.keys)).sorted()
    }
}

public extension ChangedCode {
    /// The working tree's change against `revision`, untracked files included.
    ///
    /// The after side is the working tree, since that is what a run builds; a removal has no after side and is left out, and so is a declaration move whose text did not change.
    static func inWorkingTree(against revision: String, git: GitContext) throws -> ChangedCode {
        var changes = try git.dirtySwiftFiles()
        if try git.head().map({ git.commitHash(revision) != git.commitHash($0) }) ?? false {
            let dirty = Set(changes.map(\.path))
            changes += try git.changedSwiftFiles(from: revision, to: "HEAD").filter { !dirty.contains($0.path) }
        }
        let live = changes.filter {
            if case .deleted = $0.kind {
                false
            } else {
                true
            }
        }
        let old = try git.blobs(live.map { change in
            if case let .renamed(from) = change.kind {
                return (rev: revision, path: from)
            }
            return (rev: revision, path: change.path)
        })
        var found: [ChangedDeclaration] = []
        var touched: [String: Set<Int>] = [:]
        for (offset, change) in live.enumerated() {
            guard let new = try? Data(contentsOf: git.repoRoot.appendingPathComponent(change.path)) else { continue }
            let hunks = LineDiff.hunks(old: old[offset].map { LineDiff.lines(of: $0) } ?? [], new: LineDiff.lines(of: new))
            let rewritten = hunks.flatMap { $0.new.map { $0 + 1 } }
            if !rewritten.isEmpty {
                touched[change.path] = Set(rewritten)
            }
            let file = FileDiff.compare(path: change.path, status: old[offset] == nil ? .added : .modified, lineStat: nil, bytes: (old[offset], new))
            for entry in file.changes where entry.kind != .removed && !(entry.kind == .moved && entry.movedIntact) {
                let lines = entry.newSpans.map { $0.line ... $0.endLine }
                guard !lines.isEmpty else { continue }
                found.append(ChangedDeclaration(path: change.path, label: entry.label, lines: lines))
            }
        }
        let sorted = found.sorted { ($0.path, $0.lines[0].lowerBound) < ($1.path, $1.lines[0].lowerBound) }
        return ChangedCode(declarations: sorted, lines: touched)
    }
}
