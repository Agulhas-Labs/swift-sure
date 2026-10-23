//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A changed file that is not Swift is named on the limits line, because no reference leads from it and the answer would otherwise read as though it were not part of the change.
@Suite(.serialized, .temporaryDirectories)
struct AffectedNonSwiftFilesTests {
    /// A Swift change and a non-Swift one in the working tree: the second is named beside the first's declarations.
    @Test
    func aNonSwiftFileChangedBesideASwiftOneIsNamed() async throws {
        let root = try Self.seededRepo()
        try TestSources.write("public struct Gizmo { public func added() {} }\n", to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write("--indent 2\n", to: ".swiftformat", in: root)

        let output = try await Self.affected(root)

        #expect(output.contains("1 changed file is not Swift, so no reference leads from it — a test that reads it by path is not listed: .swiftformat"), "\(output)")
        #expect(output.contains("changed files (1)"), "\(output)")
    }

    /// Only a non-Swift change: the empty answer does not claim nothing changed, and the limits name the file.
    @Test
    func onlyANonSwiftChangeIsNotReportedAsNothingChanged() async throws {
        let root = try Self.seededRepo()
        try TestSources.write("alpha\n", to: "Docs/names.txt", in: root)

        let output = try await Self.affected(root)

        #expect(!output.contains("nothing changed"), "\(output)")
        #expect(output.contains("(nothing examined — no .swift file differs, and the files that did change are not Swift; see the limits below)"), "\(output)")
        #expect(output.contains("not Swift, so no reference leads from it — a test that reads it by path is not listed: Docs/names.txt"), "\(output)")
    }

    /// A committed range with two non-Swift files names both, sorted, in the plural.
    @Test
    func aRangeNamesItsNonSwiftFiles() async throws {
        let root = try Self.seededRepo()
        try TestSources.write("public struct Gizmo { public func added() {} }\n", to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write("--indent 2\n", to: ".swiftformat", in: root)
        try TestSources.write("alpha\n", to: "Distribution/names.txt", in: root)
        try TestSources.commitAll(in: root, message: "edits")

        let output = try await Self.affected(root, range: AffectedOptions.CommitRange(from: "HEAD~1", to: "HEAD"))

        #expect(output.contains("2 changed files are not Swift, so no reference leads from them — a test that reads one by path is not listed: .swiftformat, Distribution/names.txt"), "\(output)")
    }

    /// A deleted non-Swift file is named too: a test that reads a fixture by path breaks when the fixture goes.
    @Test
    func aDeletedNonSwiftFileIsNamed() async throws {
        let root = try Self.seededRepo()
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes.txt"))
        try TestSources.write("public struct Gizmo { public func added() {} }\n", to: "Sources/Lib/Gizmo.swift", in: root)

        let output = try await Self.affected(root)

        #expect(output.contains("1 changed file is not Swift"), "\(output)")
        #expect(output.contains("notes.txt"), "\(output)")
    }

    /// With no non-Swift change the clause is absent.
    @Test
    func noNonSwiftChangeAddsNoClause() async throws {
        let root = try Self.seededRepo()
        try TestSources.write("public struct Gizmo { public func added() {} }\n", to: "Sources/Lib/Gizmo.swift", in: root)

        let output = try await Self.affected(root)

        #expect(!output.contains("not Swift"), "\(output)")
        #expect(output.contains("changed files (1)"), "\(output)")
    }
}

private extension AffectedNonSwiftFilesTests {
    /// A committed repository with one Swift file and one text file, no manifest and no build.
    static func seededRepo() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("public struct Gizmo {}\n", to: "Sources/Lib/Gizmo.swift", in: root)
        try TestSources.write("keep\n", to: "notes.txt", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        return root
    }

    static func affected(_ root: URL, range: AffectedOptions.CommitRange? = nil) async throws -> String {
        let engine = try SiftEngine(directory: root)
        try await engine.awaitSemanticStore()
        let freshness = try await engine.ensureFresh()
        return try await engine.affected(options: AffectedOptions(range: range, depth: AffectedOptions.defaultDepth), freshness: freshness)
    }
}
