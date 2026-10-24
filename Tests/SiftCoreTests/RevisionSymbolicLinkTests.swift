//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A revision's answer reads a symbolic link from that revision's tree, never from the working tree's `lstat`.
///
/// The same path can be a file at one commit and a link today, or the reverse, and the working tree says nothing about which it was then.
@Suite(.temporaryDirectories)
struct RevisionSymbolicLinkTests {
    static var drum: String {
        "enum Drum {\n    static func stock() -> Int {\n        1\n    }\n}\n"
    }

    static var kick: String {
        "enum Kick {\n    static func stock() -> Int {\n        2\n    }\n}\n"
    }

    /// Replaces the file at `path` with a symbolic link to `target`, or writes a link where there was none.
    static func link(_ path: String, to target: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        if (try? url.checkResourceIsReachable()) == true || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
    }

    /// Replaces a symbolic link at `path` with a regular file holding `source`.
    static func unlink(_ path: String, writing source: String, in root: URL) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        try TestSources.write(source, to: path, in: root)
    }

    static func head(of root: URL) throws -> String {
        try TestSources.runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A file at the revision that is a link in the working tree is still that revision's file, answered by `where` and by a digest of its path.
    @Test
    func aFileAtTheRevisionIsReadThoughTheWorkingTreeHoldsALink() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.drum, to: "Sources/Links/Drum.swift", in: root)
        try TestSources.write(Self.kick, to: "Sources/Links/Link.swift", in: root)
        try TestSources.commitAll(in: root, message: "drum and kick")
        let head = try Self.head(of: root)
        try Self.link("Sources/Links/Link.swift", to: "Drum.swift", in: root)
        let engine = try SiftEngine(directory: root)

        let found = try await engine.lookup(symbol: "Kick.stock", at: head)
        let digest = try engine.digest(targets: ["Sources/Links/Link.swift"], at: head, options: DigestOptions())

        #expect(found.contains("Sources/Links/Link.swift:2-4"), "\(found)")
        #expect(digest.contains("enum Kick"), "\(digest)")
        #expect(!digest.contains("symbolic link"), "\(digest)")
    }

    /// A link at the revision is left out of that revision's answer though the working tree holds a file there, and a digest of its path names the rule.
    @Test
    func aLinkAtTheRevisionIsLeftOutThoughTheWorkingTreeHoldsAFile() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.drum, to: "Sources/Links/Drum.swift", in: root)
        try Self.link("Sources/Links/Link.swift", to: "Drum.swift", in: root)
        try TestSources.commitAll(in: root, message: "drum and a link to it")
        let head = try Self.head(of: root)
        try Self.unlink("Sources/Links/Link.swift", writing: Self.kick, in: root)
        let engine = try SiftEngine(directory: root)

        let found = try await engine.lookup(symbol: "Drum", at: head)
        let digest = try engine.digest(targets: ["Sources/Links/Link.swift"], at: head, options: DigestOptions())

        #expect(found.contains("of 1 Swift file"), "\(found)")
        #expect(digest.contains("Sources/Links/Link.swift exists at \(head.prefix(8)) but is excluded: it is a symbolic link"), "\(digest)")
    }

    /// The tests a range affects are sought from a file both commits hold as a file, though the working tree holds a link there.
    @Test
    func anAffectedRangeKeepsAFileThoughTheWorkingTreeHoldsALink() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.drum, to: "Sources/Links/Drum.swift", in: root)
        try TestSources.write(Self.kick, to: "Sources/Links/Link.swift", in: root)
        try TestSources.commitAll(in: root, message: "drum and kick")
        let first = try Self.head(of: root)
        try TestSources.write(Self.kick.replacingOccurrences(of: "enum Kick {\n", with: "enum Kick {\n    static func tune() {}\n"), to: "Sources/Links/Link.swift", in: root)
        try TestSources.commitAll(in: root, message: "tune the kick")
        let second = try Self.head(of: root)
        try Self.link("Sources/Links/Link.swift", to: "Drum.swift", in: root)
        let engine = try SiftEngine(directory: root)
        try await engine.awaitSemanticStore()
        let freshness = try await engine.ensureFresh()

        let answer = try await engine.affected(options: AffectedOptions(range: AffectedOptions.CommitRange(from: first, to: second)), freshness: freshness)

        #expect(answer.contains("changed files (1)"), "\(answer)")
        #expect(answer.contains("Sources/Links/Link.swift — added or modified"), "\(answer)")
    }

    /// A file a range turns into a link is named as deleted by the tests it affects, since the link holds no source.
    @Test
    func anAffectedRangeNamesAFileThatBecameALinkAsDeleted() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.drum, to: "Sources/Links/Drum.swift", in: root)
        try TestSources.write(Self.kick, to: "Sources/Links/Link.swift", in: root)
        try TestSources.commitAll(in: root, message: "drum and kick")
        let first = try Self.head(of: root)
        try Self.link("Sources/Links/Link.swift", to: "Drum.swift", in: root)
        try TestSources.commitAll(in: root, message: "kick becomes a link")
        let second = try Self.head(of: root)
        let engine = try SiftEngine(directory: root)
        try await engine.awaitSemanticStore()
        let freshness = try await engine.ensureFresh()

        let answer = try await engine.affected(options: AffectedOptions(range: AffectedOptions.CommitRange(from: first, to: second)), freshness: freshness)

        #expect(answer.contains("Sources/Links/Link.swift — deleted"), "\(answer)")
        #expect(!answer.contains("added or modified"), "\(answer)")
    }
}
