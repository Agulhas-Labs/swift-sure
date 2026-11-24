//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `where X --files` lists files to open or edit, so a file deleted since the last build is counted in one closing line, never a row.
@Suite(.temporaryDirectories, .serialized)
struct WhereFilesDeletedFoldTests {
    private static var fold: String {
        "  + 2 files deleted since the last build also named it (`--refs` lists them)"
    }

    private static func collector(deleted: Int) -> WhereFilesCollector {
        let collector = WhereFilesCollector()
        collector.recordCode(path: "Live.swift", lines: [1, 2])
        for index in 1 ... deleted {
            collector.recordCode(path: "Gone\(index).swift", lines: [1], state: .deleted)
        }
        return collector
    }

    /// One live row, no row for the deleted file, and the fold line last, plural and singular.
    @Test
    func aDeletedFileIsOneClosingLineNotARow() {
        let plural = Self.collector(deleted: 2).lines(query: "X", kept: [], offset: 0)
        let singular = Self.collector(deleted: 1).lines(query: "X", kept: [], offset: 0)

        #expect(plural.suffix(3) == ["  Live.swift (2)", Self.fold, "drop --files for each reference's line"], "\(plural)")
        #expect(!plural.contains { $0.contains("Gone") || $0.contains("(file deleted") }, "\(plural)")
        #expect(singular.suffix(2) == ["  + 1 file deleted since the last build also named it (`--refs` lists them)", "drop --files for each reference's line"], "\(singular)")
    }

    /// The heading counts the listed files only and says nothing of deletion, while a changed file keeps its count and mark.
    @Test
    func theHeadingCountsListedFilesAndKeepsTheChangedMark() {
        let collector = Self.collector(deleted: 2)
        collector.recordCode(path: "Changed.swift", lines: [5], state: .modifiedSinceBuild)

        let lines = collector.lines(query: "X", kept: [], offset: 0)

        #expect(lines.contains("files naming X (2 files: 2 with code sites, 0 with not-code mentions, 1 file changed since last build):"), "\(lines)")
        #expect(lines.contains("  Changed.swift (1)  (file changed since last build)"), "\(lines)")
        #expect(!lines.joined(separator: "\n").contains("files deleted since last build"), "\(lines)")
    }

    /// The cap, the skipped line, the past-end line and the `truncated:` offset run over listed files, and every page ends in the fold line.
    @Test
    func pagingCoversListedFilesAndEveryPageEndsInTheFold() {
        let collector = WhereFilesCollector()
        for index in 1 ... 3 {
            collector.recordCode(path: "F\(index).swift", lines: [1])
        }
        collector.recordCode(path: "A.swift", lines: [1], state: .deleted)
        collector.recordCode(path: "Z.swift", lines: [1], state: .deleted)

        let first = collector.lines(query: "X", kept: [], offset: 0, cap: 2)
        let second = collector.lines(query: "X", kept: [], offset: 2, cap: 2)
        let past = collector.lines(query: "X", kept: [], offset: 9, cap: 2)

        #expect(first.suffix(5) == ["  F1.swift (1)", "  F2.swift (1)", "  truncated: 1 more file — pass offset 2 to continue", Self.fold, "drop --files for each reference's line"], "\(first)")
        #expect(second.suffix(4) == ["  (…2 files skipped)", "  F3.swift (1)", Self.fold, "drop --files for each reference's line"], "\(second)")
        #expect(past.suffix(2) == ["  offset 9 is past the last of 3 files — drop offset to see them", Self.fold], "\(past)")
    }

    /// End to end: `--files` folds a file deleted after the build, and `--refs` still lists it as a labelled row.
    @Test
    func refsStillListsTheDeletedFile() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Lib\", targets: [.target(name: \"Lib\")])\n", to: "Package.swift", in: root)
        try TestSources.write("public struct Gizmo {}\n", to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write("public func make() -> Gizmo {\n    Gizmo()\n}\n", to: "Sources/Lib/Make.swift", in: root)
        try TestSources.write("public func other() -> Gizmo {\n    Gizmo()\n}\n", to: "Sources/Lib/Other.swift", in: root)
        try TestSources.commitAll(in: root, message: "deleted fold fixture")
        try await TestSources.swiftBuild(packageAt: root)
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        try await engine.awaitSemanticStore()
        _ = try await engine.ensureFresh()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Lib/Other.swift"))

        let files = try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true, filesOnly: true))
        let refs = try await engine.lookup(symbol: "Gizmo", freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))

        #expect(files.contains("  Sources/Lib/Make.swift (2)"), "\(files)")
        #expect(!files.contains("\n  Sources/Lib/Other.swift"), "\(files)")
        #expect(files.hasSuffix("  + 1 file deleted since the last build also named it (`--refs` lists them)\n\("drop --files for each reference's line")"), "\(files)")
        #expect(refs.contains("Sources/Lib/Other.swift"), "\(refs)")
        #expect(refs.contains("(file deleted since last build)"), "\(refs)")
    }
}
