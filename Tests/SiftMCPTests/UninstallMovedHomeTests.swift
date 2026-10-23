//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// `--purge` deletes the home a variable moved only while it holds nothing but what the tool writes there, so a variable set to the wrong directory cannot empty one of the user's.
@Suite(.temporaryDirectories)
struct UninstallMovedHomeTests {
    private typealias Fixture = UninstallCommandTests

    /// A directory outside the scratch home holding `entries`, each a file unless its name ends in `/`, one spelled `<dir>/<name>` a file inside that directory.
    private static func movedHome(_ entries: [String]) throws -> URL {
        let directory = try TemporaryDirectory.make("uninstall-moved-home")
        for entry in entries {
            let url = directory.appendingPathComponent(entry)
            if entry.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try "inside".write(to: url.appendingPathComponent("inside.jsonl"), atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "\(entry) bytes".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        return directory
    }

    /// Every file under `directory`, by its path inside it, with its bytes.
    private static func snapshot(_ directory: URL) throws -> [String: Data] {
        let paths = FileManager.default.subpaths(atPath: directory.path) ?? []
        var files: [String: Data] = [:]
        for path in paths where PathKind.of(directory.appendingPathComponent(path)) == .file {
            files[path] = try Data(contentsOf: directory.appendingPathComponent(path))
        }
        return files
    }

    @Test
    func aMovedHomeHoldingAFileTheToolDidNotWriteSurvivesPurge() throws {
        let installed = try Fixture.install()
        let home = try Self.movedHome(["notes.txt", "run.jsonl"])
        let before = try Self.snapshot(home)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], adding: ["SWIFT_SURE_HOME": home.path], remover: Fixture.ServerRemover())

        #expect(status == 1)
        #expect(try Self.snapshot(home) == before)
        #expect(before.count == 2)
        let refused = "not purged: \(home.path) is the directory SWIFT_SURE_HOME names, holding notes.txt, which swift-sure did not write — remove it by hand"
        #expect(lines.contains(refused), "\(lines)")
        #expect(lines.contains("purged: \(home.path)") == false)
    }

    @Test
    func aMovedHomeHoldingOnlyWhatTheToolWritesIsPurged() throws {
        let installed = try Fixture.install()
        let home = try Self.movedHome(["run.jsonl", "advice/suppressions.jsonl", "advice/a-session_1.json", "advice/backoff/", "callers/session.1-ab.json"])

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], adding: ["SWIFT_SURE_HOME": home.path], remover: Fixture.ServerRemover())

        #expect(status == 0, "\(lines)")
        #expect(PathKind.of(home) == .absent)
        #expect(lines.contains("purged: \(home.path)"), "\(lines)")
    }

    @Test
    func anOverrideNamingTheDefaultHomeIsPurgedAsTheDefault() throws {
        let installed = try Fixture.install()
        try "theirs".write(to: installed.siftHome.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], adding: ["SWIFT_SURE_HOME": installed.siftHome.path], remover: Fixture.ServerRemover())

        #expect(status == 0, "\(lines)")
        #expect(PathKind.of(installed.siftHome) == .absent)
        #expect(lines.contains("purged: \(installed.siftHome.path)"), "\(lines)")
    }

    @Test
    func theEarlierHomeVariableIsRefusedTheSameWay() throws {
        let installed = try Fixture.install()
        let home = try Self.movedHome(["notes.txt", "photos/", "usage.jsonl"])
        let before = try Self.snapshot(home)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], adding: ["SIFT_HOME": home.path], remover: Fixture.ServerRemover())

        #expect(status == 1)
        #expect(try Self.snapshot(home) == before)
        #expect(before.count == 3)
        let refused = "not purged: \(home.path) is the directory SIFT_HOME names, holding notes.txt and 1 more entry swift-sure did not write — remove it by hand"
        #expect(lines.contains(refused), "\(lines)")
    }

    @Test
    func aFileTheToolDidNotWriteInsideItsAdviceDirectoryStopsThePurge() throws {
        let installed = try Fixture.install()
        let home = try Self.movedHome(["run.jsonl", "advice/thesis.docx"])
        let before = try Self.snapshot(home)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], adding: ["SWIFT_SURE_HOME": home.path], remover: Fixture.ServerRemover())

        #expect(status == 1)
        #expect(try Self.snapshot(home) == before)
        let refused = "not purged: \(home.path) is the directory SWIFT_SURE_HOME names, holding advice/thesis.docx, which swift-sure did not write — remove it by hand"
        #expect(lines.contains(refused), "\(lines)")
    }

    @Test
    func anEntryOfAKindTheToolDoesNotWriteUnderItsNameStopsThePurge() throws {
        let installed = try Fixture.install()
        let home = try Self.movedHome(["run.jsonl/", "callers"])
        let before = try Self.snapshot(home)

        let (lines, status) = try Fixture.exiting(installed, ["--purge"], adding: ["SWIFT_SURE_HOME": home.path], remover: Fixture.ServerRemover())

        #expect(status == 1)
        #expect(try Self.snapshot(home) == before)
        let refused = "not purged: \(home.path) is the directory SWIFT_SURE_HOME names, holding callers and 1 more entry swift-sure did not write — remove it by hand"
        #expect(lines.contains(refused), "\(lines)")
    }

    @Test
    func whatAppearsInAMovedHomeAfterTheListingStopsTheDelete() throws {
        let scratch = try TemporaryDirectory.make("uninstall-moved-home-late")
        let home = try Self.movedHome(["run.jsonl"])
        let locations = SiftUninstall.Locations(
            settings: scratch.appendingPathComponent("settings.json"),
            claudeConfig: scratch.appendingPathComponent(".claude.json"),
            rule: scratch.appendingPathComponent("rule.md"),
            siftHome: home,
            homeOverride: "SWIFT_SURE_HOME",
            logs: []
        )
        let caches = SiftUninstall.leftCaches(locations, roots: [])
        try #require(caches.map(\.refusal) == [nil], "\(caches)")
        try "theirs".write(to: home.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let step = UninstallPurge.settle(caches, purge: true)

        #expect(step.failures == 1)
        #expect(step.purged.isEmpty)
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("notes.txt").path))
        #expect(step.notes == ["not purged: \(home.path) is the directory SWIFT_SURE_HOME names, holding notes.txt, which swift-sure did not write — remove it by hand"])
    }
}
