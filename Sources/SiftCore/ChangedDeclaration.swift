//
// Copyright © Agulhas Labs
//

import Foundation

/// A declaration a change added, changed or moved, with the after-side lines it answers for — what coverage is measured over.
public struct ChangedDeclaration: Sendable, Equatable {
    /// The file, repository-relative.
    public let path: String
    /// The declaration as `diff` addresses it: its container path and its name.
    public let label: String
    /// The after-side lines this declaration answers for, as `diff` pairs them — a type matched on both sides answers only for its own lines.
    public let lines: [ClosedRange<Int>]

    public init(path: String, label: String, lines: [ClosedRange<Int>]) {
        self.path = path
        self.label = label
        self.lines = lines
    }
}

public extension ChangedDeclaration {
    /// Every declaration the working tree added, changed or moved against `revision`, untracked files included, in path and line order.
    ///
    /// The after side is the working tree, since that is what a run builds; a removal has no after side and is left out, and so is a move whose text did not change.
    static func inWorkingTree(against revision: String, git: GitContext) throws -> [ChangedDeclaration] {
        try ChangedCode.inWorkingTree(against: revision, git: git).declarations
    }
}
