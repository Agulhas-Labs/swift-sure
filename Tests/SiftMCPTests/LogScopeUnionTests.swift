//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// One `--root` argument names one directory for the call log and the run log together, and every face that reads both (the `report` page) takes that scope, or its refusal, from the union.
///
/// The two logs hold different sets of roots by construction, so resolving a fragment separately against each let one heading carry two repositories' numbers.
@Suite(.temporaryDirectories)
struct LogScopeUnionTests {
    // MARK: Fixtures

    private static func writeLines(_ lines: [String], named name: String) throws -> URL {
        let file = try TemporaryDirectory.make(name).appendingPathComponent("\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func line(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func callLog(roots: [String]) throws -> URL {
        try writeLines(roots.map { root in
            line(["tool": "digest", "target": "Widget", "root": root, "ms": 5, "ok": true, "ts": "2026-08-18T10:00:00Z"])
        }, named: "scope-union-usage")
    }

    private static func runLog(roots: [String]) throws -> URL {
        try writeLines(roots.map { root in
            line(["kind": "swift test", "exit": 0, "ms": 900, "shown": 4, "total": 200, "root": root, "ts": "2026-08-18T11:00:00Z"])
        }, named: "scope-union-run")
    }

    /// The `report` page's data over the two logs, for the root asked.
    private static func page(calls: URL, runs: URL, root: String, includeScratch: Bool = false) throws -> ReportData {
        try ReportData.assemble(
            logURL: calls, runLogURL: runs, projectsDirectory: TemporaryDirectory.make("scope-union-projects"),
            roots: [], since: nil, root: root, includeScratch: includeScratch, now: Date(),
            timeZone: TimeZone(identifier: "UTC") ?? .current, moduleHealth: { _ in nil }
        )
    }

    private static func matches(_ result: Result<LogScope?, UsageScan.Problem>) -> [String]? {
        if case let .failure(.rootAmbiguous(_, matches)) = result {
            return matches
        }
        return nil
    }

    private static func refused(_ data: ReportData, argument: String) -> Bool {
        data.rootScope == .unresolved(argument: argument) && data.calls == 0 && data.runs == nil
    }

    // MARK: One argument, one directory

    /// Two checkouts of one name, one known only to each log, are one refusal listing both, and no figure survives it.
    @Test
    func twoSameNamedCheckoutsAcrossTheTwoLogsAreOneRefusalListingBoth() throws {
        let calls = try Self.callLog(roots: ["/work/Catalogue"])
        let runs = try Self.runLog(roots: ["/personal/Catalogue"])

        let resolution = LogScope.resolve("Catalogue", inLogsAt: [calls, runs])
        let data = try Self.page(calls: calls, runs: runs, root: "Catalogue")

        #expect(Self.matches(resolution) == ["/personal/Catalogue", "/work/Catalogue"])
        #expect(Self.refused(data, argument: "Catalogue"))
        #expect(data.logNote?.contains("Catalogue matches 2 paths in the logs") == true)
    }

    /// Ambiguous to the calls, unambiguous to the runs: the runs half does not guess beside the refusal.
    @Test
    func aFragmentAmbiguousInTheCallLogRefusesForTheRunsToo() throws {
        let calls = try Self.callLog(roots: ["/work/Catalogue", "/personal/Catalogue"])
        let runs = try Self.runLog(roots: ["/personal/Catalogue"])

        #expect(Self.matches(LogScope.resolve("Catalogue", inLogsAt: [calls, runs]))?.count == 2)
        #expect(try Self.refused(Self.page(calls: calls, runs: runs, root: "Catalogue"), argument: "Catalogue"))
    }

    /// Ambiguous to the runs alone: a refusal, not a run section that vanishes and reads as "nothing was wrapped".
    @Test
    func aFragmentAmbiguousInTheRunLogRefusesRatherThanVanishing() throws {
        let calls = try Self.callLog(roots: ["/work/Catalogue"])
        let runs = try Self.runLog(roots: ["/work/Catalogue", "/personal/Catalogue"])

        let data = try Self.page(calls: calls, runs: runs, root: "Catalogue")

        #expect(Self.matches(LogScope.resolve("Catalogue", inLogsAt: [calls, runs]))?.count == 2)
        #expect(Self.refused(data, argument: "Catalogue"))
        #expect(data.logNote?.contains("matches 2 paths in the logs") == true)
    }

    /// Unique across the union scopes both halves.
    @Test
    func aFragmentUniqueInTheUnionScopesBothHalves() throws {
        let calls = try Self.callLog(roots: ["/work/Catalogue/app"])
        let runs = try Self.runLog(roots: ["/work/Catalogue/app"])

        let scope = try LogScope.resolve("Catalogue", inLogsAt: [calls, runs]).get()
        let data = try Self.page(calls: calls, runs: runs, root: "Catalogue")

        #expect(scope?.path == "/work/Catalogue")
        #expect(data.rootScope == .resolved("/work/Catalogue"))
        #expect(data.calls == 1)
        #expect(data.runs?.runs == 1)
        #expect(data.runs?.days == ["2026-08-18"])
    }

    /// A root only one log has seen still resolves, and the other half is empty rather than unresolved.
    @Test
    func aRootRecordedInOnlyOneLogResolvesForBoth() throws {
        let calls = try Self.callLog(roots: ["/work/Catalogue"])
        let runs = try Self.runLog(roots: ["/work/Other"])

        let data = try Self.page(calls: calls, runs: runs, root: "Catalogue")

        #expect(data.rootScope == .resolved("/work/Catalogue"))
        #expect(data.calls == 1)
        #expect(data.runs == nil)
    }

    // MARK: What a refusal is allowed to print

    private static let roots = [
        "/Users/hometester/Developer/Alpha/app",
        "/Users/hometester/Developer/Beta/app",
        "/Users/hometester/Developer/Solo",
    ]

    private static var redactor: Redactor {
        Redactor(salt: Data("log-scope-union-salt".utf8))
    }

    /// A redacted refusal names the candidates as fragments a reader can retype, and nothing of the machine.
    @Test
    func aRedactedRefusalNamesTheCandidatesWithoutNamingTheMachine() throws {
        let runs = try Self.runLog(roots: Self.roots)

        let rendered = RunFailureHistoryReport.render(fileURL: runs, root: "zzznope", redactor: Self.redactor)

        #expect(!rendered.contains("hometester"))
        #expect(!rendered.contains("/Users/"))
        for root in Self.roots {
            #expect(!rendered.contains(root))
        }
        #expect(rendered.contains("\n  Alpha/app"))
        #expect(rendered.contains("\n  Beta/app"))
        #expect(rendered.contains("\n  Solo"))

        // `--unredact` is unchanged: the reader who asked for the paths still gets them.
        let unredacted = RunFailureHistoryReport.render(fileURL: runs, root: "zzznope", redactor: nil)

        #expect(unredacted.contains("/Users/hometester/Developer/Alpha/app"))
    }

    /// The ambiguous branch obeys the same rule, and each fragment it offers resolves to the directory it was printed for.
    @Test
    func anAmbiguousRefusalOffersFragmentsTheCommandAccepts() throws {
        let runs = try Self.runLog(roots: Self.roots)

        let rendered = RunFailureHistoryReport.render(fileURL: runs, root: "app", redactor: Self.redactor)

        #expect(rendered.contains("app matches 2 paths in the run log — name one:"))
        #expect(rendered.contains("\n  Alpha/app"))
        #expect(rendered.contains("\n  Beta/app"))
        #expect(!rendered.contains("hometester"))
        #expect(LogScope.spellings(of: Self.roots, redacted: true) == ["Alpha/app", "Beta/app", "Solo"])
        for (fragment, directory) in [("Alpha/app", Self.roots[0]), ("Beta/app", Self.roots[1]), ("Solo", Self.roots[2])] {
            let resolved = try LogScope.resolve(fragment, among: Set(Self.roots)).get()
            #expect(resolved.path == directory)
        }
    }

    // MARK: Canonicalisation

    /// One directory reaching the two logs under two spellings is one directory, not an ambiguity.
    @Test
    func twoSpellingsOfOneDirectoryAcrossTheTwoLogsResolveTogether() throws {
        let root = try TemporaryDirectory.make("scope-union-case")
        defer { try? FileManager.default.removeItem(at: root) }
        let shouted = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent.uppercased()).path
        try #require(FileManager.default.fileExists(atPath: shouted), "case-sensitive volume — nothing to fold")
        let calls = try Self.callLog(roots: [root.path])
        let runs = try Self.runLog(roots: [shouted])

        let resolution = LogScope.resolve(root.lastPathComponent, inLogsAt: [calls, runs])
        let data = try Self.page(calls: calls, runs: runs, root: root.lastPathComponent, includeScratch: true)

        #expect(Self.matches(resolution) == nil)
        #expect(data.calls == 1)
        #expect(data.runs?.runs == 1)
    }
}
