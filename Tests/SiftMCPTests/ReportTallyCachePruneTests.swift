//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Which entries a report's save drops from the tally cache: only those its own sweep would have listed, and never one it just listed.
@Suite(.temporaryDirectories) struct ReportTallyCachePruneTests {
    private typealias Cases = ReportTallyCacheTests

    private static func date(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text), sourceLocation: sourceLocation)
    }

    private static func report(_ fixture: Cases.Fixture, over projects: URL, since: String) {
        _ = ReportData.assemble(
            logURL: fixture.log,
            projectsDirectory: projects,
            roots: [],
            since: since,
            root: nil,
            now: Cases.now,
            timeZone: Cases.utc,
            tallyCache: fixture.cache,
            moduleHealth: { _ in nil }
        )
    }

    /// A subagent transcript under `session`, written at `modified`.
    @discardableResult
    private static func writeSubagent(of session: URL, modified: Date) throws -> URL {
        let directory = session.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Cases.write([Cases.digest("b", at: "2026-08-13T10:00:00Z")], to: directory.appendingPathComponent("agent-one.jsonl"), modified: modified)
    }

    /// A report over an empty directory lists nothing of the entries read under another, so it leaves them.
    @Test
    func aReportOverAnotherProjectsDirectoryKeepsTheEntriesReadUnderThisOne() throws {
        let fixture = try Cases.fixture()
        let recent = try Self.date("2026-08-15T12:00:00Z")
        let transcript = try Cases.write([Cases.digest("a", at: "2026-08-15T10:00:00Z")], to: fixture.project.appendingPathComponent("one.jsonl"), modified: recent)
        let empty = fixture.directory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let projects = fixture.directory.appendingPathComponent("projects")
        Self.report(fixture, over: projects, since: "7d")
        let before = try Cases.storedKeys(fixture)
        #expect(!before.isEmpty)
        #expect(!before.isDisjoint(with: Cases.keys(of: transcript)))

        Self.report(fixture, over: empty, since: "7d")
        #expect(try Cases.storedKeys(fixture) == before)

        try FileManager.default.removeItem(at: transcript)
        Self.report(fixture, over: projects, since: "7d")
        #expect(try Cases.storedKeys(fixture).isEmpty)
    }

    /// An entry the run listed and stored stays however long ago its transcript was last written: a subagent under a session resumed today.
    @Test
    func anEntryTheRunListedSurvivesTheRetention() throws {
        let fixture = try Cases.fixture()
        let session = try Cases.write([Cases.digest("a", at: "2026-08-16T10:00:00Z")], to: fixture.project.appendingPathComponent("one.jsonl"), modified: Self.date("2026-08-16T11:00:00Z"))
        let agent = try Self.writeSubagent(of: session, modified: Self.date("2026-05-08T12:00:00Z"))

        Self.report(fixture, over: fixture.directory.appendingPathComponent("projects"), since: "7d")

        #expect(try !Cases.keys(of: agent).isDisjoint(with: Cases.storedKeys(fixture)))
    }

    /// A subagent newer than its session, which a narrower window does not list, is kept while its file exists.
    @Test
    func aSubagentOfASessionOutsideTheWindowSurvivesANarrowerRun() throws {
        let fixture = try Cases.fixture()
        let session = try Cases.write([Cases.digest("a", at: "2026-08-07T10:00:00Z")], to: fixture.project.appendingPathComponent("one.jsonl"), modified: Self.date("2026-08-07T12:00:00Z"))
        let agent = try Self.writeSubagent(of: session, modified: Self.date("2026-08-13T12:00:00Z"))
        let projects = fixture.directory.appendingPathComponent("projects")
        Self.report(fixture, over: projects, since: "30d")
        #expect(try !Cases.keys(of: agent).isDisjoint(with: Cases.storedKeys(fixture)))

        Self.report(fixture, over: projects, since: "7d")
        #expect(try !Cases.keys(of: agent).isDisjoint(with: Cases.storedKeys(fixture)))

        try FileManager.default.removeItem(at: agent)
        Self.report(fixture, over: projects, since: "30d")
        #expect(try Cases.keys(of: agent).isDisjoint(with: Cases.storedKeys(fixture)))
    }
}
