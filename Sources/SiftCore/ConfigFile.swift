//
// Copyright © Agulhas Labs
//

import Foundation

/// The one place that names `.swift-sure.json`'s location, so every reader and watcher of it looks at the same file.
///
/// The file is yours to write by hand; this version never rewrites it, so a key it does not model is read past and left exactly where it is.
struct ConfigFile {
    /// Where this repository's config is read from.
    static func url(repoRoot: URL) -> URL {
        SiftPaths.config(in: repoRoot)
    }
}
