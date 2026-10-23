//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the one promise the path helpers make beyond naming: asking where something goes never puts it there.
@Suite(.temporaryDirectories)
struct SiftPathsTests {
    /// Asking where the cache is must not be what creates it — the callers that only read would start leaving directories in every repository they touch.
    @Test
    func askingWhereTheCacheIsCreatesNothing() throws {
        let root = try TestSources.makeTempDirectory()

        let cache = SiftPaths.cache(in: root)

        #expect(cache.lastPathComponent == SiftPaths.directoryName)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    /// A repository with no config at all is the common case, and what it gets asked for is where a config would go.
    @Test
    func askingWhereTheConfigIsCreatesNothing() throws {
        let root = try TestSources.makeTempDirectory()

        let config = SiftPaths.config(in: root)

        #expect(config.lastPathComponent == SiftPaths.configFileName)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
