//
// Copyright © Agulhas Labs
//

import Foundation

/// How a ledger record spells the directory its run was made in, shared by every command that files one so a sharded `swift-sure test` proof and a `swift-sure run` proof match under `run --proved`.
struct RunDirectory {
    /// `workingDirectory`, relative to `root` — `"."` for the root itself, the same spelling ``TreeContentHash/invocation(of:in:repositoryRoot:)`` uses, so a nested package's suite and the whole repository's never stand for each other in the ledger while the same relative directory in a second worktree still matches.
    static func name(of workingDirectory: URL, relativeTo root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path
        let directory = workingDirectory.resolvingSymlinksInPath().path
        return directory == rootPath ? "." : directory.hasPrefix(rootPath + "/") ? String(directory.dropFirst(rootPath.count + 1)) : directory
    }
}
