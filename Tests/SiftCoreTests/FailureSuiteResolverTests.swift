//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A failure's printed line names its suite only while the file still reads as it did when indexed.
@Suite(.temporaryDirectories)
struct FailureSuiteResolverTests {
    private static var source: String {
        "struct PalletTests {\n    func lifts() {}\n}\n\nstruct GizmoTests {\n    func spins() {}\n}\n"
    }

    /// An unedited file resolves a line inside a function to the suite around it.
    @Test
    func aFreshFileResolvesToItsSuite() async throws {
        let root = try await Self.indexedRoot()
        let resolver = try #require(FailureSuiteResolver(repositoryRoot: root))

        #expect(resolver.suite(of: "spins()", atLocation: "Gizmo.swift:6:5") == "GizmoTests")
    }

    /// An edit that moved the line into the other suite resolves to the suite the line is in now.
    @Test
    func aFileEditedAfterIndexingResolvesToTheSuiteTheLineIsInNow() async throws {
        let root = try await Self.indexedRoot()
        let resolver = try #require(FailureSuiteResolver(repositoryRoot: root))
        let edited = "struct PalletTests {\n    func lifts() {}\n    func spins() {}\n}\n\nstruct GadgetTests {\n    func turns() {}\n}\n"
        try TestSources.write(edited, to: "Sources/Gizmo.swift", in: root)

        #expect(resolver.suite(of: "spins()", atLocation: "Gizmo.swift:3:5") == "PalletTests")
        #expect(resolver.suite(of: "turns()", atLocation: "Gizmo.swift:7:5") == "GadgetTests")
    }

    /// An edited file whose line sits in no function of that name says nothing.
    @Test
    func anEditedFileWithNoFunctionOfThatNameResolvesToNothing() async throws {
        let root = try await Self.indexedRoot()
        let resolver = try #require(FailureSuiteResolver(repositoryRoot: root))
        try TestSources.write("// two lines\n// added\n" + Self.source, to: "Sources/Gizmo.swift", in: root)

        #expect(resolver.suite(of: "lifts()", atLocation: "Gizmo.swift:6:5") == nil)
    }

    /// Failures in one edited file share a single parse of it.
    @Test
    func manyFailuresInOneEditedFileParseItOnce() async throws {
        let root = try await Self.indexedRoot()
        var parses = 0
        let resolver = try #require(FailureSuiteResolver(repositoryRoot: root) { url, path in
            parses += 1
            return FileParser.parse(absoluteURL: url, repoRelativePath: path)
        })
        try TestSources.write("// one line added\n" + Self.source, to: "Sources/Gizmo.swift", in: root)

        #expect(resolver.suite(of: "lifts()", atLocation: "Gizmo.swift:3:5") == "PalletTests")
        #expect(resolver.suite(of: "spins()", atLocation: "Gizmo.swift:7:5") == "GizmoTests")
        #expect(resolver.suite(of: "spins()", atLocation: "Gizmo.swift:7:5") == "GizmoTests")
        #expect(parses == 1)
    }

    /// A file whose stat matches its row is answered from the stored rows: here the rows, doctored to match the file's current stat, still place the line in the suite the text no longer has.
    @Test
    func aFileMatchingItsRowIsAnsweredFromTheStoredRows() async throws {
        let root = try await Self.indexedRoot()
        let edited = "struct PalletTests {\n    func lifts() {}\n    func spins() {}\n}\n\nstruct GadgetTests {\n    func turns() {}\n}\n"
        try TestSources.write(edited, to: "Sources/Gizmo.swift", in: root)
        let current = try #require(FileParser.parse(absoluteURL: root.appendingPathComponent("Sources/Gizmo.swift"), repoRelativePath: "Sources/Gizmo.swift"))
        let stale = FileParser.parse(source: Self.source, repoRelativePath: "Sources/Gizmo.swift", alongside: { _, _ in }).file
        let doctored = ParsedFile(
            path: current.path,
            size: current.size,
            mtime: current.mtime,
            contentHash: stale.contentHash,
            imports: stale.imports,
            parseErrorCount: 0,
            symbols: stale.symbols
        )
        let databasePath = SiftPaths.cache(in: root).appendingPathComponent(SiftPaths.indexFileName).path
        try IndexStore(databasePath: databasePath).replaceFiles([doctored]) { _ in ("Sources", false) }
        let resolver = try #require(FailureSuiteResolver(repositoryRoot: root))

        // In the file's text line 6 is a type declaration, not `spins()`; only the stored rows put `spins()` there, in GizmoTests.
        #expect(resolver.suite(of: "spins()", atLocation: "Gizmo.swift:6:5") == "GizmoTests")
    }

    private static func indexedRoot() async throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(source, to: "Sources/Gizmo.swift", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        try await SiftEngine(directory: root).ensureFresh()
        return root
    }
}
