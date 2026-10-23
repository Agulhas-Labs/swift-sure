//
// Copyright © Agulhas Labs
//

import Foundation

/// The count of tracked files other than `.swift` that differ from HEAD, for the `raw:` line's tree stamp.
///
/// Staged and unstaged changes both count, a deletion included; untracked files do not. A tree whose only movement is a manifest, a fixture or a document a test reads is not the commit it was tested at, though no Swift file moved.
struct TrackedNonSwiftChanges {
    /// The number of modified tracked non-Swift files in `git`'s working tree, or `nil` where git would not answer.
    static func count(in git: GitContext) -> Int? {
        guard let output = try? GitContext.run(
            arguments: ["status", "--porcelain", "-z", "--untracked-files=no", "--", ".", ":(exclude)*.swift"],
            in: git.repoRoot, within: ChildDeadline.gitBulk
        ) else {
            return nil
        }
        return entries(in: output)
    }

    /// Entries in `-z` porcelain output: a rename or copy carries its original path as one further token, which is not an entry.
    static func entries(in output: String) -> Int {
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: true)
        var count = 0
        var index = 0
        while index < tokens.count {
            let entry = tokens[index]
            index += 1
            guard entry.count > 3 else { continue }
            count += 1
            let status = entry.prefix(2)
            if status.contains("R") || status.contains("C") {
                index += 1
            }
        }
        return count
    }
}
