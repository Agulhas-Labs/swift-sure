//
// Copyright © Agulhas Labs
//

import Foundation

/// The lines of one file a range edited, asked about in working-tree numbering.
///
/// The range's own line diff names the lines its after side edited. Where the after side is not the working tree, a working-tree line is one of those only where the line diff of the after side against the working tree carries it unchanged from such a line; a line the working tree added since is not an edit of the range.
struct CheckupEditedLines {
    /// The after side's lines (0-based) the range's line diff added or replaced.
    private let edited: IndexSet
    /// The hunks turning the after side into the working tree; none where the after side is the working tree.
    private let sinceAfterSide: [LineDiff.Hunk]

    /// `before` and `after` are the range's two sides, `nil` where the file does not exist on that side; `workingTree` is the file on disk when the after side is another revision.
    init(before: Data?, after: Data?, workingTree: Data?) {
        let afterLines = after.map(LineDiff.lines) ?? []
        let rangeHunks = LineDiff.hunks(old: before.map(LineDiff.lines) ?? [], new: afterLines)
        edited = rangeHunks.reduce(into: IndexSet()) { $0.insert(integersIn: $1.new) }
        sinceAfterSide = workingTree.map { LineDiff.hunks(old: afterLines, new: LineDiff.lines(of: $0)) } ?? []
    }

    /// Whether the working-tree `line` (1-based) is a line the range edited.
    func contains(workingTreeLine line: Int) -> Bool {
        let index = line - 1
        var shift = 0
        for hunk in sinceAfterSide {
            if hunk.new.contains(index) {
                return false
            }
            if hunk.new.upperBound <= index {
                shift += hunk.new.count - hunk.old.count
            }
        }
        return edited.contains(index - shift)
    }
}
