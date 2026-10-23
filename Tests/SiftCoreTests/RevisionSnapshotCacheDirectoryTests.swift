//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A syntactic answer read from a past revision leaves the cache directory as it found it: absent where it was absent, there where it was there.
@Suite(.temporaryDirectories)
struct RevisionSnapshotCacheDirectoryTests {
    @Test
    func aLookupAtARevisionLeavesNoCacheDirectoryWhereThereWasNone() async throws {
        let root = try Self.makeRepo()
        let cache = SiftPaths.cache(in: root)
        try #require(!FileManager.default.fileExists(atPath: cache.path))

        let answer = try await SiftEngine(directory: root, storesNothing: true).lookup(symbol: "Widget", at: "HEAD")

        #expect(answer.contains("Sources/Lib/Widget.swift"), "\(answer)")
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test
    func aLookupAtARevisionKeepsACacheDirectoryThatWasThereBeforeIt() async throws {
        let root = try Self.makeRepo()
        let cache = SiftPaths.cache(in: root)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        _ = try await SiftEngine(directory: root, storesNothing: true).lookup(symbol: "Widget", at: "HEAD")

        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("at").path))
    }
}

private extension RevisionSnapshotCacheDirectoryTests {
    static func makeRepo() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("public struct Widget {}\n", to: "Sources/Lib/Widget.swift", in: root)
        try TestSources.commitAll(in: root, message: "first")
        return root
    }
}
