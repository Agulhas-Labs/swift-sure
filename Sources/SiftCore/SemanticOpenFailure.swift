//
// Copyright © Agulhas Labs
//

import Foundation

/// How a refused open of an index store is worded in the note that carries it.
struct SemanticOpenFailure {
    /// One line for why `error` stopped the open: where the semantic cache under `.swift-sure/` could not be written, that it could not, and otherwise the error as it came.
    ///
    /// The directory named is the one `repoRoot`'s checkout uses.
    ///
    /// A tree nobody may write has no `.swift-sure/isdb` to put the store's copy in, and the platform's own text for that names a scratch directory the reader never made and cannot see.
    static func cause(of error: Error, in repoRoot: URL) -> String {
        guard IndexLocation.isPermissionRefusal(error) else { return "\(error)" }
        return "the semantic cache under \(SiftPaths.cache(in: repoRoot).lastPathComponent)/ cannot be written in this tree"
    }
}
