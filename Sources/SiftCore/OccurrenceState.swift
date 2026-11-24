//
// Copyright © Agulhas Labs
//

/// Where one occurrence's file stands against the build that recorded it (Docs/Design.md §2).
///
/// The declaring file's mtime check never covered this: it asks whether the symbol's *own* file moved, which says nothing about the files the store names as calling, referencing, overriding or conforming to it. Those can be edited — or deleted outright — with the declaration untouched, and only a build clears what the store still holds about them.
public enum OccurrenceState: Sendable, Equatable, CaseIterable {
    /// The file is present and no newer than the store's last build — the row stands as recorded.
    case live
    /// The file is not in the working tree at all.
    ///
    /// The occurrence is provably dead, and nothing but a build removes it from the store.
    case deleted
    /// The file is not in the working tree, and a build without cleaning keeps its record, so only a clean build removes the occurrence from the store.
    case keptDeletion
    /// The file is still there but has been written since the build, so the line this row names may have moved, or the occurrence may be gone.
    case modifiedSinceBuild

    /// The trailing label a listed row carries, or `nil` when the row is trustworthy as recorded.
    var marker: String? {
        switch self {
        case .live: nil
        case .deleted: "  (file deleted since last build)"
        case .keptDeletion: "  (file deleted; its record stays until a clean build)"
        case .modifiedSinceBuild: "  (file changed since last build)"
        }
    }

    /// Whether the file is gone from the tree, whether or not a build keeps its record.
    var isDeleted: Bool {
        self == .deleted || self == .keptDeletion
    }

    var isLive: Bool {
        if case .live = self {
            return true
        }
        return false
    }
}

extension OccurrenceState {
    /// The state a file keeps when two accounts of it meet: the first non-live one, except that a plain deletion outranks a deletion a build keeps, since the header counts it as the plain one whichever came first.
    func settled(with other: OccurrenceState) -> OccurrenceState {
        if isLive {
            return other
        }
        return self == .keptDeletion && other == .deleted ? .deleted : self
    }
}
