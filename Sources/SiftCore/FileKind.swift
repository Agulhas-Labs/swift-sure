//
// Copyright © Agulhas Labs
//

/// What a cited file is against its own build: each file an answer cites is exactly one of these, ordered worst first, the precedence a file judged twice is counted under.
enum FileKind: Int, Comparable {
    /// `stat` cannot read the file.
    case deleted
    /// `stat` cannot read the file, and a build without cleaning keeps its record: it lies inside the root, was dropped at or before the build, and a unit on disk still names it (``KeptDeletions``).
    case keptDeletion
    /// A store holds a unit for the file, and it changed after its newest one.
    case changed
    /// No store holds a unit for the file, its module is one a build of the store's project compiles, and it changed after the store's newest unit.
    case new
    /// No store holds a unit for the file, and either no build of the store's project compiles its module or a build ran after its change and wrote none.
    case notBuilt
    /// A store holds a unit for the file and it has not changed since, or the index has no row for it at all.
    case current

    static func < (lhs: FileKind, rhs: FileKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether the file is gone from the tree, whether or not a build keeps its record.
    var isDeleted: Bool {
        self == .deleted || self == .keptDeletion
    }

    /// The axis state a row in a file of this kind takes.
    var occurrenceState: OccurrenceState {
        switch self {
        case .deleted: .deleted
        case .keptDeletion: .keptDeletion
        case .changed, .new: .modifiedSinceBuild
        case .notBuilt, .current: .live
        }
    }
}
