//
// Copyright © Agulhas Labs
//

import Foundation

/// Where `swift-sure test` builds in a linked worktree: inside it, so the build goes when the worktree does.
///
/// **Without a path, `xcodebuild` builds into the shared `~/Library/Developer/Xcode/DerivedData/<Scheme>-<hash>`**, and a worktree that is removed leaves its build there for good (176.5 GB orphaned on one machine). A linked worktree therefore gets `<worktree>/.swift-sure/DerivedData`; the primary checkout, a directory in no repository, and a git that does not answer get nothing and keep today's command lines.
public struct WorktreeDerivedData {
    /// The answer's line naming `directory`, the one a run chose, the path printed relative to the worktree root.
    public static func line(for directory: URL) -> String {
        "derived data \(directory.deletingLastPathComponent().lastPathComponent)/DerivedData — inside this worktree, so it goes when the worktree is removed"
    }

    /// The directory `swift-sure test` chooses for a build in `repositoryRoot`, or `nil` when it chooses none.
    ///
    /// A `-derivedDataPath` in the caller's pass-through wins. The `rev-parse` is bounded by `bound` (``ChildDeadline/git``) here and ``GitContext/directories(of:)`` is left alone, because a git that timed out elsewhere must never be read as no repository; here the same silence only means no path is chosen. The path is chosen only once `.swift-sure/` is excluded in the repository, already or just written, so `git worktree remove` without `--force` still works; a common directory that cannot be written chooses nothing.
    public static func chosen(repositoryRoot: URL, passThrough: [String], within bound: TimeInterval = ChildDeadline.git) -> URL? {
        guard !passThrough.contains("-derivedDataPath") else { return nil }
        guard let directories = GitContext.directories(of: repositoryRoot, within: bound), directories.own != directories.common else { return nil }
        guard GitContext(repoRoot: repositoryRoot).cacheIsExcluded(inCommonDirectory: directories.common) else { return nil }
        let directory = SiftPaths.cache(in: repositoryRoot).appendingPathComponent("DerivedData", isDirectory: true)
        ignoreContents(of: directory)
        return directory
    }

    /// Writes `*` to an ignore file in `directory` unless it has one, so a recursive search that honours those files but not `info/exclude` (an agent's ugrep) does not walk the build.
    ///
    /// Best effort: a directory that cannot be made leaves the build to fail on its own terms. A file already there is never touched.
    private static func ignoreContents(of directory: URL) {
        let file = directory.appendingPathComponent(".gitignore")
        let manager = FileManager.default
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              !manager.fileExists(atPath: file.path) else { return }
        try? Data("*\n".utf8).write(to: file)
    }
}
