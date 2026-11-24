//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how a query words a cited file deleted before the last build: a build without cleaning keeps that file's record, so "since last build" would send the reader to a build that changes nothing (Docs/Design.md §2).
@Suite(.temporaryDirectories)
struct QueryKeptDeletionTests {
    static var keptLabel: String {
        "(file deleted; its record stays until a clean build)"
    }

    /// Deleted, then built: the row, the heading and the header each say a clean build clears it, and the answer locates no line in the file.
    @Test
    func aDeletionTheBuildKeptIsMarkedUntilACleanBuild() async throws {
        let root = try await Self.deletedThenBuilt()

        let output = try await Self.lookup("helper()", in: root)
        let swept = try await Self.lookup("Widget", in: root, options: WhereOptions(includeReferences: true))

        #expect(output.contains("Sources/Lib/Extra.swift (1):  " + Self.keptLabel), "\(output)")
        #expect(output.contains("1 deleted file kept until a clean build"), "\(output)")
        #expect(output.contains("semantic: stale until a clean build (1 cited file deleted: Sources/Lib/Extra.swift)"), "\(output)")
        #expect(!output.contains("since last build"), "\(output)")
        #expect(swept.contains(Self.keptLabel), "\(swept)")
        #expect(swept.contains("1 deleted file kept until a clean build"), "\(swept)")
        #expect(!ExactAnswer.locations(inWhereAnswer: swept).contains { $0.path == "Sources/Lib/Extra.swift" }, "\(swept)")
    }

    /// Built, then deleted, with no build after: a build does clear it, so the wording stays what it was.
    @Test
    func aDeletionAfterTheBuildKeepsSinceLastBuild() async throws {
        let root = try await Self.makeRepo()
        _ = try await SiftEngine(directory: root).ensureFresh()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Lib/Extra.swift"))

        let output = try await Self.lookup("helper()", in: root)

        #expect(output.contains("Sources/Lib/Extra.swift (1):  (file deleted since last build)"), "\(output)")
        #expect(output.contains("1 file deleted since last build"), "\(output)")
        #expect(output.contains("semantic: stale since last build (1 cited file deleted: Sources/Lib/Extra.swift)"), "\(output)")
        #expect(!output.contains("until a clean build"), "\(output)")
    }

    /// A changed file beside the kept deletion: a build clears that part, so the header stays `since last build`, and the heading counts both.
    @Test
    func aChangedFileBesideTheKeptDeletionKeepsSinceLastBuild() async throws {
        let root = try await Self.deletedThenBuilt()
        try TestSources.write("public func alsoCallsHelper() {\n    helper()\n}\n// edited\n", to: "Sources/Lib/Other.swift", in: root)

        let output = try await Self.lookup("helper()", in: root)

        #expect(output.contains("semantic: stale since last build (2 cited files: 1 changed, 1 deleted)"), "\(output)")
        #expect(output.contains("1 file changed since last build, 1 deleted file kept until a clean build"), "\(output)")
        #expect(output.contains("Sources/Lib/Extra.swift (1):  " + Self.keptLabel), "\(output)")
        #expect(!output.contains("semantic: stale until"), "\(output)")
    }

    /// A kept deletion in an answer that is otherwise partial, its test target never built: a build adds what the answer lacks, so the header stays `since last build`.
    @Test
    func aPartialAnswerKeepsSinceLastBuild() async throws {
        let root = try await Self.deletedThenBuilt(withTestTarget: true)

        let output = try await Self.lookup("helper()", in: root)

        #expect(output.contains("Sources/Lib/Extra.swift (1):  " + Self.keptLabel), "\(output)")
        #expect(output.contains("semantic: stale since last build (1 cited file deleted: Sources/Lib/Extra.swift)"), "\(output)")
        #expect(!output.contains("semantic: stale until"), "\(output)")
    }

    /// A site heading marked as a kept deletion is not taken for a located file, as one marked deleted since the build is not.
    @Test
    func aKeptRowIsNeverLocated() {
        for mark in ["  " + Self.keptLabel, "  (file deleted since last build)"] {
            let answer = """
            semantic: fresh

            callers of Lib.helper() (1):
              Sources/Lib/Extra.swift (1):\(mark)
                :2  callsHelper()
            """
            #expect(ExactAnswer.locations(inWhereAnswer: answer).isEmpty, "\(mark)")
        }
    }

    /// `--files` folds a kept deletion into a tail line of its own, worded as the row label is.
    @Test
    func theFilesListingFoldsAKeptDeletionApart() async throws {
        let root = try await Self.deletedThenBuilt()

        let files = try await Self.lookup("Widget", in: root, options: WhereOptions(includeReferences: true, filesOnly: true))

        #expect(files.contains("  + 1 deleted file kept until a clean build also named it (`--refs` lists them)"), "\(files)")
        #expect(!files.contains("deleted since the last build"), "\(files)")
        #expect(!files.contains("  Sources/Lib/Extra.swift"), "\(files)")
    }

    /// A package whose two callers of `helper()` live in files of their own, so deleting one leaves the declaration, and optionally a test target a plain build leaves without a unit.
    private static func makeRepo(withTestTarget: Bool = false) async throws -> URL {
        let root = try TestSources.makeTempRepo()
        let tests = withTestTarget ? ", .testTarget(name: \"LibTests\", dependencies: [\"Lib\"])" : ""
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Lib",
                targets: [.target(name: "Lib")\(tests)]
            )
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write("public struct Widget {\n    public init() {}\n}\n\npublic func helper() {}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.write("public func callsHelper() {\n    helper()\n    _ = Widget()\n}\n", to: "Sources/Lib/Extra.swift", in: root)
        try TestSources.write("public func alsoCallsHelper() {\n    helper()\n}\n", to: "Sources/Lib/Other.swift", in: root)
        if withTestTarget {
            try TestSources.write("import Lib\nimport Testing\n\n@Test func makes() {\n    _ = Widget()\n}\n", to: "Tests/LibTests/LibTests.swift", in: root)
        }
        try TestSources.commitAll(in: root, message: "kept deletion fixture")
        try await TestSources.swiftBuild(packageAt: root)
        return root
    }

    /// Builds the fixture, lets the index see it, deletes `Sources/Lib/Extra.swift`, lets the index notice, and builds again without cleaning.
    private static func deletedThenBuilt(withTestTarget: Bool = false) async throws -> URL {
        let root = try await makeRepo(withTestTarget: withTestTarget)
        _ = try await SiftEngine(directory: root).ensureFresh()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Lib/Extra.swift"))
        _ = try await SiftEngine(directory: root).ensureFresh()
        try await TestSources.swiftBuild(packageAt: root)
        return root
    }

    private static func lookup(_ symbol: String, in root: URL, options: WhereOptions = WhereOptions()) async throws -> String {
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        return try await engine.lookup(symbol: symbol, freshness: engine.ensureFresh(), options: options)
    }
}
