//
// Copyright © Agulhas Labs
//

import Foundation

/// Compares one touched file's two sides — the storeless comparison `affected`'s after-edit seeds and the session-resume block share.
///
/// Parsing never touches the persisted index: each side is parsed fresh from the bytes the caller holds, one file at a time (Docs/Design.md §2).
struct DiffGatherer {
    /// One touched file compared from the bytes of both sides, `nil` for a side that does not exist.
    static func fileDiff(_ change: GitContext.Change, old: Data?, new: Data?) -> FileDiff {
        let status: FileDiff.Status = if let from = change.renamedFrom {
            .renamed(from: from)
        } else if old == nil {
            .added
        } else if new == nil {
            .deleted
        } else {
            .modified
        }
        return FileDiff.compare(path: change.path, status: status, bytes: (old, new))
    }
}

extension GitContext.Change {
    /// The path a rename moved this file from, `nil` for anything else.
    var renamedFrom: String? {
        if case let .renamed(from) = kind {
            return from
        }
        return nil
    }
}
