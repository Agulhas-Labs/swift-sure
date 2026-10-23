//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A member's callers after a refactor moved them out of two files into a new one: each deleted file's rows sit under a heading that labels it, after the live files, and the moved call is listed whether or not a build has seen its new file.
@Suite(.temporaryDirectories, .serialized)
struct WhereMovedCallerTests {
    private static var deleted: String {
        "(file deleted since last build)"
    }

    /// The headings of the two deleted files under `release`'s callers, in either order: the order among labelled files is not the answer's.
    private static let deletedHeadings: Set = ["  Sources/Lib/Parallel.swift (2):  \(deleted)", "  Sources/Lib/Check.swift (1):  \(deleted)"]

    /// A package whose two members are called from two files the test deletes, one of them holding several calls, and from one file it keeps.
    private static func makeBuiltRepo() async throws -> URL {
        let root = try TestSources.makeTempRepo()
        let files = [
            "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Lib\", targets: [.target(name: \"Lib\")])\n",
            "Sources/Lib/Core.swift": "public final class DepotStore {\n    public init() {}\n    public func release(_ value: Int) {}\n}\n\npublic struct DepotBox {\n    public init() {}\n    public func stop() {}\n}\n\npublic struct DepotCatalog {\n    public let pool = DepotStore()\n    public let stop = DepotBox()\n    public init() {}\n}\n",
            "Sources/Lib/Parallel.swift": "public func callsHelper(_ parallel: DepotCatalog) {\n    parallel.pool.release(1)\n    parallel.pool.release(2)\n    parallel.stop.stop()\n}\n",
            "Sources/Lib/Check.swift": "public func check(_ pool: DepotStore) {\n    pool.release(4)\n}\n",
            "Sources/Lib/Live.swift": "public func live(_ pool: DepotStore, _ stopper: DepotBox) {\n    pool.release(5)\n    stopper.stop()\n}\n",
        ]
        for (path, text) in files {
            try TestSources.write(text, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "moved caller fixture")
        try await TestSources.swiftBuild(packageAt: root)
        return root
    }

    /// Deletes the two calling files and writes the moved calls into a new one.
    private static func move(in root: URL) throws {
        try FileManager.default.removeItem(at: root.appending(path: "Sources/Lib/Parallel.swift"))
        try FileManager.default.removeItem(at: root.appending(path: "Sources/Lib/Check.swift"))
        try TestSources.write("public func crateData(_ parallel: DepotCatalog) {\n    parallel.pool.release(1)\n    parallel.stop.stop()\n}\n", to: "Sources/Lib/GizmoTools.swift", in: root)
    }

    /// The file headings under `heading`, in order.
    private static func fileHeadings(under heading: String, in answer: String) -> [String] {
        let all = answer.split(separator: "\n").map(String.init)
        guard let start = all.firstIndex(where: { $0.hasPrefix(heading) }) else { return [] }
        return all[(start + 1)...].prefix { $0.hasPrefix("  ") }.filter { !$0.hasPrefix("    ") }
    }

    /// Before any rebuild: the deleted files' rows follow the live one under labelled headings, and the new file's call is listed by name.
    @Test
    func aMemberSweepAfterAMoveLabelsEachDeletedFileAndListsTheNewOne() async throws {
        let root = try await Self.makeBuiltRepo()
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        _ = try await engine.ensureFresh()
        try Self.move(in: root)

        let answer = try await engine.lookup(symbol: "DepotStore.release", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

        #expect(answer.contains("semantic: stale since last build (3 cited files: 2 deleted, 1 new)"), "\(answer)")
        let headings = Self.fileHeadings(under: "callers of Lib.DepotStore.release(_:) (", in: answer)
        #expect(headings.first == "  Sources/Lib/Live.swift (1):", "\(answer)")
        #expect(Set(headings.dropFirst()) == Self.deletedHeadings, "\(answer)")
        #expect(answer.contains("new since last build, not in the store, mention the name: Sources/Lib/GizmoTools.swift:2"), "\(answer)")
    }

    /// After a rebuild the store still holds the deleted files' units: their rows stay labelled, and the moved call is a caller row of its own.
    @Test
    func aRebuildAfterTheMoveListsTheMovedCallerAndStillLabelsTheDeletedFiles() async throws {
        let root = try await Self.makeBuiltRepo()
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        _ = try await engine.ensureFresh()
        try Self.move(in: root)
        try TestSources.commitAll(in: root, message: "move the callers")
        try await TestSources.swiftBuild(packageAt: root)

        let release = try await engine.lookup(symbol: "DepotStore.release", freshness: engine.ensureFresh())
        let stop = try await engine.lookup(symbol: "DepotBox.stop", freshness: engine.ensureFresh())

        #expect(release.contains("semantic: stale since last build (2 cited files deleted)"), "\(release)")
        let headings = Self.fileHeadings(under: "callers of Lib.DepotStore.release(_:) (", in: release)
        #expect(headings.prefix(2) == ["  Sources/Lib/Live.swift (1):", "  Sources/Lib/GizmoTools.swift (1):"], "\(release)")
        #expect(Set(headings.dropFirst(2)) == Self.deletedHeadings, "\(release)")
        #expect(stop.contains("    :3  crateData(_:)  | parallel.stop.stop()"), "\(stop)")
        #expect(Self.fileHeadings(under: "callers of Lib.DepotBox.stop() (", in: stop).last == "  Sources/Lib/Parallel.swift (1):  \(Self.deleted)", "\(stop)")
    }
}
