//
// Copyright © Agulhas Labs
//

import Foundation

/// The one-line refusal for a command whose whole effect is a file in the tree, asked of a tree nobody may write.
///
/// `index` refuses through ``EngineError/treeNotWritable(_:)``; this is the same refusal for the command that would otherwise end in the platform's own words about a file it never needed to name.
public struct TreeWritability {
    /// Throws where `run --without` could not make the `.swift-sure/` its set-aside lives in.
    public static func requireSetAsideStore(repoRoot: URL) throws {
        guard !SiftEngine.wouldKeepIndexInMemory(root: repoRoot) else {
            throw EngineError.cannotWrite(path: repoRoot.path, doing: "there is nowhere to set the change aside (\(SiftPaths.cache(in: repoRoot).lastPathComponent)/) — run the tests without --without")
        }
    }
}
