//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The `raw:` line's tree stamp counts tracked files other than `.swift` that moved, apart from the Swift count.
@Suite(.temporaryDirectories)
struct RunRawLineCountsOtherModifiedFilesTests {
    @Test
    func theStampAddsTheOtherFilesCountedApartFromTheSwiftOnes() {
        let tree = WorkingTree(repository: "Widget", worktree: nil)

        #expect(Freshness.stamp(of: tree, headShort: "cc94af6", dirtyCount: 0, otherModified: 2) == "Widget @ cc94af6 (Swift clean, 2 other files modified)")
        #expect(Freshness.stamp(of: tree, headShort: "cc94af6", dirtyCount: 0, otherModified: 1) == "Widget @ cc94af6 (Swift clean, 1 other file modified)")
        #expect(Freshness.stamp(of: tree, headShort: "cc94af6", dirtyCount: 3, otherModified: 2) == "Widget @ cc94af6 (Swift dirty: 3, 2 other files modified)")
        #expect(Freshness.stamp(of: tree, headShort: "cc94af6", dirtyCount: 3, otherModified: 0) == "Widget @ cc94af6 (Swift dirty: 3)")
        #expect(Freshness.stamp(of: tree, headShort: "cc94af6", dirtyCount: nil, otherModified: 2) == "Widget @ cc94af6")
    }

    @Test
    func aModifiedTrackedDocumentIsCountedAndAnUntrackedFileIsNot() throws {
        let root = try TestSources.makeTempRepo()
        let swift = try Self.fakeSwift(in: root)
        try "notes\n".write(to: root.appendingPathComponent("NOTES.md"), atomically: true, encoding: .utf8)
        try TestSources.commitAll(in: root, message: "settle")
        let outcome = try RunLauncher(workingDirectory: root, repositoryRoot: root).run([swift.path, "test"])
        try "stray\n".write(to: root.appendingPathComponent("stray.txt"), atomically: true, encoding: .utf8)

        let untrackedOnly = try #require(outcome.filteredAnswer(workingDirectory: root, stamped: true)?.text)
        #expect(Self.rawLine(in: untrackedOnly).contains(" (Swift clean) · "))

        try "edited\n".write(to: root.appendingPathComponent("NOTES.md"), atomically: true, encoding: .utf8)
        let one = try #require(outcome.filteredAnswer(workingDirectory: root, stamped: true)?.text)
        #expect(Self.rawLine(in: one).contains(" (Swift clean, 1 other file modified) · "))

        try "edited\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try TestSources.runGit(["add", "README.md"], in: root)
        let two = try #require(outcome.filteredAnswer(workingDirectory: root, stamped: true)?.text)
        #expect(Self.rawLine(in: two).contains(" (Swift clean, 2 other files modified) · "))

        try "struct Widget {}\n".write(to: root.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        let both = try #require(outcome.filteredAnswer(workingDirectory: root, stamped: true)?.text)
        #expect(Self.rawLine(in: both).contains(" (Swift dirty: 1, 2 other files modified) · "))
    }

    @Test
    func aRenameCountsOnceAndNothingChangedCountsNone() {
        #expect(TrackedNonSwiftChanges.entries(in: "R  new.md\0old.md\0 M other.md\0") == 2)
        #expect(TrackedNonSwiftChanges.entries(in: "") == 0)
    }

    private static func rawLine(in answer: String) -> String {
        answer.split(separator: "\n").last { $0.hasPrefix("raw: ") }.map(String.init) ?? ""
    }

    /// A stand-in `swift` that prints one passing Swift Testing line and exits 0.
    private static func fakeSwift(in directory: URL) throws -> URL {
        let script = directory.appendingPathComponent("swift")
        try "#!/bin/sh\necho '✔ Test run with 1 test in 1 suite passed after 0.047 seconds.'\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
