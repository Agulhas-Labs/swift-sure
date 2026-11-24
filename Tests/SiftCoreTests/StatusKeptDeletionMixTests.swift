//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `status` where deletions are dated by the directory that held them: a rename the index noticed only after the build still reads as dropped before it, and a deletion made after the build still reads as after.
@Suite(.temporaryDirectories) struct StatusKeptDeletionMixTests {
    /// A `git mv` and a build in one command: the index notices the rename after the build, yet the build kept the old unit, so only a clean build clears it.
    @Test
    func aRenameNoticedOnlyAfterTheBuildReadsUntilACleanBuild() async throws {
        let root = try await SemanticWhereTests.makeBuiltRepo()
        _ = try await SiftEngine(directory: root).ensureFresh()
        try TestSources.runGit(["mv", "Sources/Lib/Caller.swift", "Sources/Lib/Calling.swift"], in: root)
        try await TestSources.swiftBuild(packageAt: root)

        let status = try await Self.status(in: root)

        #expect(status.contains("semantic: stale until a clean build (1 file deleted:"))
    }

    /// One deletion kept by the build beside one made after it, in another directory: the later one is a change a build clears, so the line says `since last build`.
    @Test
    func aKeptDeletionBesideOneAfterTheBuildReadsSinceLastBuild() async throws {
        let root = try await SemanticWhereTests.makeBuiltRepo()
        try TestSources.write("func extra() {}\n", to: "Sources/Lib/Sub/Extra.swift", in: root)
        try TestSources.commitAll(in: root, message: "second directory")
        try await TestSources.swiftBuild(packageAt: root)
        _ = try await SiftEngine(directory: root).ensureFresh()
        try TestSources.runGit(["mv", "Sources/Lib/Caller.swift", "Sources/Lib/Calling.swift"], in: root)
        try await TestSources.swiftBuild(packageAt: root)
        try await Task.sleep(for: .seconds(1.1))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Lib/Sub/Extra.swift"))

        let status = try await Self.status(in: root)

        #expect(status.contains("semantic: stale since last build (2 files deleted)"))
    }

    private static func status(in root: URL) async throws -> String {
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        return try await engine.statusText(freshness: engine.ensureFresh())
    }
}
