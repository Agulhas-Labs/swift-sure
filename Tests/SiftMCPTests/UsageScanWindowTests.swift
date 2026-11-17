//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// What a scan over the usage log keeps for a `--since` day and a `--root` directory, and how it reads a damaged or missing log: the narrowing every face (`report`, `audit`) draws its figures from.
@Suite(.temporaryDirectories)
struct UsageScanWindowTests {
    // MARK: Fixtures

    private static func writeLog(_ lines: [String]) throws -> URL {
        let file = try TemporaryDirectory.make("usage-window").appendingPathComponent("usage.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func entry(
        tool: String,
        target: String? = nil,
        root: String = "/repo/a",
        timestamp: String = "2026-07-30T10:00:00Z",
        bytes: (out: Int, source: Int)? = nil,
        intercepted: String? = nil
    ) -> String {
        var object: [String: Any] = ["tool": tool, "root": root, "ms": 10, "ok": true, "ts": timestamp]
        object["target"] = target
        if let bytes {
            object["outBytes"] = bytes.out
            object["srcBytes"] = bytes.source
        }
        if let intercepted {
            object["via"] = "hook"
            object["intercepted"] = intercepted
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func mixedLog() throws -> URL {
        try writeLog([
            entry(tool: "digest", target: "Old", root: "/repo/a", timestamp: "2026-07-28T09:00:00Z"),
            entry(tool: "digest", target: "Recent", root: "/repo/a", timestamp: "2026-07-30T09:00:00Z"),
            entry(tool: "where", target: "Recent", root: "/work/Orchard/app", timestamp: "2026-07-30T10:00:00Z"),
        ])
    }

    /// The scan of `file` for `since` and the root fragment `root`, resolved against that log the way a face resolves it.
    private static func scan(_ file: URL, since: String? = nil, root: String? = nil) throws -> UsageScan {
        let scope = try LogScope.resolve(root, inLogsAt: [file]).get()
        return try UsageScan.load(fileURL: file, since: since, scope: scope).get()
    }

    // MARK: Window and root

    @Test
    func sinceKeepsOnlyDaysOnOrAfterIt() throws {
        let scan = try Self.scan(Self.mixedLog(), since: "2026-07-30")

        #expect(scan.entries.count == 2)
        #expect(scan.entries.map(\.day) == ["2026-07-30", "2026-07-30"])
        #expect(!scan.entries.contains { $0.target == "Old" })
        #expect(scan.since == "2026-07-30")
        #expect(scan.logged == 3)
    }

    @Test
    func rootNarrowsToOneRepository() throws {
        let scan = try Self.scan(Self.mixedLog(), root: "/repo/a")

        #expect(scan.entries.count == 2)
        #expect(scan.resolvedRoot == "/repo/a")
        #expect(!scan.sweptSubtree)
        #expect(!scan.entries.contains { $0.root == "/work/Orchard/app" })
    }

    @Test
    func aTrailingPathFragmentResolvesToTheFullRoot() throws {
        let scan = try Self.scan(Self.mixedLog(), root: "Orchard/app")

        #expect(scan.resolvedRoot == "/work/Orchard/app")
        #expect(scan.entries.count == 1)
    }

    @Test
    func anAmbiguousFragmentAsksRatherThanPickingARepository() throws {
        let file = try Self.writeLog([
            Self.entry(tool: "digest", root: "/one/app"),
            Self.entry(tool: "digest", root: "/two/app"),
        ])

        let resolution = LogScope.resolve("app", inLogsAt: [file])

        guard case let .failure(.rootAmbiguous(argument, matches)) = resolution else {
            Issue.record("expected an ambiguity, got \(resolution)")
            return
        }

        #expect(argument == "app")
        #expect(matches == ["/one/app", "/two/app"])
    }

    /// Calls are logged against the app checkout while the product is what gets typed.
    @Test
    func aParentDirectoryReportsTheReposBeneathIt() throws {
        let file = try Self.writeLog([
            Self.entry(tool: "digest", root: "/work/Depot/app"),
            Self.entry(tool: "where", root: "/work/Depot/app"),
        ])

        let scan = try Self.scan(file, root: "Depot")

        #expect(scan.resolvedRoot == "/work/Depot")
        #expect(scan.sweptSubtree)
        #expect(scan.entries.count == 2)
    }

    /// A stray call filed against the product folder must not shadow the checkout below it.
    @Test
    func aRootAlsoCountsTheCallsLoggedBeneathIt() throws {
        let file = try Self.writeLog([
            Self.entry(tool: "digest", root: "/work/Depot"),
            Self.entry(tool: "digest", root: "/work/Depot/app"),
            Self.entry(tool: "where", root: "/work/Depot/app"),
        ])

        let scan = try Self.scan(file, root: "Depot")

        #expect(scan.entries.count == 3)
        #expect(scan.sweptSubtree)
    }

    /// Containment is by path component, not by string prefix.
    @Test
    func aSiblingSharingANamePrefixIsNotSweptIn() throws {
        let file = try Self.writeLog([
            Self.entry(tool: "digest", root: "/work/Depot/app"),
            Self.entry(tool: "digest", root: "/work/DepotOld"),
        ])

        let scan = try Self.scan(file, root: "/work/Depot")

        #expect(scan.entries.map(\.root) == ["/work/Depot/app"])
    }

    /// A typo is told apart from genuine silence: the refusal carries the real roots.
    @Test
    func anUnknownRootSaysSoAndListsTheRealOnes() throws {
        let file = try Self.mixedLog()

        let resolution = LogScope.resolve("/repo/typo", inLogsAt: [file])

        guard case let .failure(.rootUnmatched(argument, roots)) = resolution else {
            Issue.record("expected an unmatched root, got \(resolution)")
            return
        }

        #expect(argument == "/repo/typo")
        #expect(roots == ["/repo/a", "/work/Orchard/app"])
    }

    @Test
    func bothFiltersCompose() throws {
        let scan = try Self.scan(Self.mixedLog(), since: "2026-07-30", root: "/repo/a")

        #expect(scan.entries.count == 1)
        #expect(scan.entries.first?.target == "Recent")
        #expect(scan.since == "2026-07-30")
        #expect(scan.resolvedRoot == "/repo/a")
    }

    /// The savings are scoped by the same filters as the counts beside them.
    @Test
    func savingsRespectTheSinceAndRootFilters() throws {
        func window(_ target: String, out: Int, root: String = "/repo/a", timestamp: String) -> String {
            Self.entry(tool: "digest", target: target, root: root, timestamp: timestamp, bytes: (out: out, source: 1000), intercepted: "window")
        }
        let file = try Self.writeLog([
            window("Old", out: 900, timestamp: "2026-07-28T09:00:00Z"),
            window("Recent", out: 100, timestamp: "2026-07-30T09:00:00Z"),
            window("Elsewhere", out: 900, root: "/repo/b", timestamp: "2026-07-30T09:00:00Z"),
        ])

        let savings = try #require(Self.scan(file, since: "2026-07-30", root: "/repo/a").savings)

        #expect(savings.total.calls == 1)
        #expect(savings.total.served == 100)
        #expect(savings.total.source == 1000)
    }

    // MARK: Damaged and missing logs

    @Test
    func malformedLinesAreCountedNotFatal() throws {
        let file = try Self.writeLog([
            Self.entry(tool: "digest", target: "Widget"),
            "{ half a line",
            "not json",
        ])

        let scan = try UsageScan.load(fileURL: file).get()

        #expect(scan.entries.count == 1)
        #expect(scan.malformed == 2)
    }

    /// Failures group by the reason each recorded, and one logged before failures carried a reason groups under the placeholder `report` prints, marked as not recorded.
    @Test
    func failuresAreGroupedByRecordedReason() throws {
        let file = try Self.writeLog([
            Self.entry(tool: "digest", target: "Widget"),
            #"{"err":"\"worktree\" is not field:value","ms":10,"ok":false,"root":"/repo/a","target":"worktree","tool":"search","ts":"2026-07-30T10:00:00Z"}"#,
            #"{"err":"\"worktree\" is not field:value","ms":10,"ok":false,"root":"/repo/a","target":"statusline","tool":"search","ts":"2026-07-30T10:00:00Z"}"#,
            #"{"ms":10,"ok":false,"root":"/repo/a","target":"Ghost","tool":"where","ts":"2026-07-30T10:00:00Z"}"#,
        ])

        let groups = try UsageScan.load(fileURL: file).get().failureGroups

        #expect(groups.map(\.reason) == [#""worktree" is not field:value"#, "(no reason recorded — entry predates the err field)"])
        #expect(groups.map(\.count) == [2, 1])
        #expect(groups.map(\.isRecorded) == [true, false])
    }

    @Test
    func missingLogGetsAnHonestEmptyState() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/usage.jsonl")

        guard case .failure(.missingOrEmpty) = UsageScan.load(fileURL: missing) else {
            Issue.record("a missing log must read as missing, not as zero calls")
            return
        }
        let data = try ReportData.assemble(
            logURL: missing, projectsDirectory: TemporaryDirectory.make("usage-window-projects"), roots: [],
            since: nil, root: nil, now: Date(), timeZone: TimeZone(identifier: "UTC") ?? .current, moduleHealth: { _ in nil }
        )

        #expect(data.calls == 0)
        #expect(data.logNote == "no usage recorded yet — the log is missing or empty")
    }
}
