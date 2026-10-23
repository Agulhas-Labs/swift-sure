//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the wording of `status` when the only thing it counts is a file deleted before the last build: a build keeps that file's unit until a clean build, so "since last build" would send the reader to a rebuild that cannot clear it.
@Suite(.temporaryDirectories) struct StatusDeletedBeforeBuildTests {
    /// Deleted, then built: nothing a rebuild changes, so the line says what does.
    @Test
    func aFileDeletedBeforeTheBuildIsStaleUntilACleanBuild() async throws {
        let root = try await Self.deletedThenBuilt()

        let status = try await Self.status(in: root)

        #expect(status.contains("semantic: stale until a clean build (1 file deleted: Sources/Lib/Caller.swift)"))
        #expect(!status.contains("since last build"))
        #expect(StatusRenameThenBuildTests.linesAfterTheStoreLine(of: status) == [SiftEngine.statusAxisNote, SiftEngine.statusDeletedNote])
    }

    /// A file written after the build beside the kept deletion: a build does clear that part, so the wording stays what it was.
    @Test
    func aChangedFileBesideTheKeptDeletionKeepsSinceLastBuild() async throws {
        let root = try await Self.deletedThenBuilt()
        try TestSources.write("open class Base {\n    public init() {}\n    open func greet() {}\n    open func more() {}\n}\n", to: "Sources/Lib/Base.swift", in: root)

        let status = try await Self.status(in: root)

        #expect(status.contains("semantic: stale since last build (2 files: 1 changed, 1 deleted)"))
        #expect(!status.contains("semantic: stale until"))
        #expect(StatusRenameThenBuildTests.linesAfterTheStoreLine(of: status) == [SiftEngine.statusAxisNote, SiftEngine.statusDeletedNote])
    }

    /// Builds the shared fixture, deletes `Sources/Lib/Caller.swift`, lets the index notice, and builds again.
    private static func deletedThenBuilt() async throws -> URL {
        let root = try await SemanticWhereTests.makeBuiltRepo()
        _ = try await SiftEngine(directory: root).ensureFresh()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Lib/Caller.swift"))
        _ = try await SiftEngine(directory: root).ensureFresh()
        try await TestSources.swiftBuild(packageAt: root)
        return root
    }

    private static func status(in root: URL) async throws -> String {
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        return try await engine.statusText(freshness: engine.ensureFresh())
    }
}
